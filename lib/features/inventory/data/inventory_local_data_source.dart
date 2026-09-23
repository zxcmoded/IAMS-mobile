import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import '../../masterdata/data/models/sync_metadata.dart';
import 'models/inventory_item.dart';
import 'models/inventory_item_detail.dart';

/// The SQLite gateway for the offline-first inventory **read cache** and its
/// sync bookkeeping — the `inventory_item` master table (joined against the
/// shared `stock_version_cache` for on-hand) plus the inventory-scoped
/// `sync_metadata` cursors and `inventory_reachable_snapshot`.
///
/// Mirrors `HierarchyLocalDataSource`: all inventory-cache SQL lives here and
/// nowhere else, page upserts advance their cursor in the same transaction (so
/// a crash can't leave committed rows with a stale cursor), and reads use the
/// indexed columns / an aggregate join directly rather than pulling everything
/// into Dart. `stock_version_cache` mutation writes are owned by
/// `OutboxLocalDataSource`; this class only reads that table for the join and
/// upserts synced rows into it — both hit the same table, so a reconciled
/// mutation is visible to the read path immediately.
class InventoryLocalDataSource {
  InventoryLocalDataSource(this._db);

  final AppDatabase _db;

  static const _item = 'inventory_item';
  static const _cache = 'stock_version_cache';

  // ---- Read path ------------------------------------------------------------

  /// Every cached item (optionally narrowed by a case-insensitive substring
  /// [search] over sku / name / barcode — matching the server's
  /// `ToLower().Contains`), each with its aggregate on-hand summed across all
  /// bins via a LEFT JOIN against `stock_version_cache` (items with no stock
  /// rows come back with total `0`, so they still surface under
  /// all / out_of_stock).
  ///
  /// Returns the raw per-item aggregate **unsorted, unfiltered by stock level,
  /// and unpaginated** — the repository overlays pending-outbox deltas and then
  /// applies the stock filter, sku sort, and offset pagination on the resulting
  /// *effective* on-hand (which SQL cannot know). `inventory_item` carries no
  /// `is_active` list filter because the server's `ListInventory` doesn't
  /// filter inactive items out either — it returns them with the flag.
  Future<List<InventoryItem>> aggregateItems({String? search}) async {
    final db = await _db.instance;
    final where = StringBuffer();
    final args = <Object?>[];
    final term = search?.trim().toLowerCase();
    if (term != null && term.isNotEmpty) {
      final like = '%$term%';
      where.write(
          'WHERE (LOWER(i.sku) LIKE ? OR LOWER(i.name) LIKE ? '
          "OR (i.barcode IS NOT NULL AND LOWER(i.barcode) LIKE ?))");
      args.addAll([like, like, like]);
    }
    final rows = await db.rawQuery(
      '''
      SELECT i.id, i.sku, i.barcode, i.name, i.unit_of_measure, i.category,
             i.is_active, COALESCE(SUM(s.quantity_on_hand), 0) AS total
      FROM $_item i
      LEFT JOIN $_cache s ON s.inventory_item_id = i.id
      ${where.toString()}
      GROUP BY i.id
      ''',
      args,
    );
    return rows.map(_itemFromAggregateRow).toList(growable: false);
  }

  InventoryItem _itemFromAggregateRow(Map<String, Object?> row) => InventoryItem(
        id: row['id'] as String,
        sku: row['sku'] as String,
        name: row['name'] as String,
        isActive: (row['is_active'] as int) != 0,
        totalQuantityOnHand: (row['total'] as num?)?.toDouble() ?? 0,
        barcode: row['barcode'] as String?,
        unitOfMeasure: row['unit_of_measure'] as String?,
        category: row['category'] as String?,
      );

  /// Resolves a scanned/entered code to its item, matching `barcode` **or**
  /// `sku` exactly (case-insensitive) — the offline SKU-validation lookup for
  /// the Create-Inventory flow. Barcode matches take precedence over sku so a
  /// scan of a barcode that happens to collide with another item's sku resolves
  /// to the barcode owner. Returns `null` for an unknown/blank code. Local-only,
  /// no API call.
  Future<InventoryItem?> findItemByCode(String code) async {
    final term = code.trim();
    if (term.isEmpty) return null;
    final db = await _db.instance;
    final rows = await db.rawQuery(
      '''
      SELECT i.id, i.sku, i.barcode, i.name, i.unit_of_measure, i.category,
             i.is_active, COALESCE(SUM(s.quantity_on_hand), 0) AS total
      FROM $_item i
      LEFT JOIN $_cache s ON s.inventory_item_id = i.id
      WHERE i.barcode = ? COLLATE NOCASE OR i.sku = ? COLLATE NOCASE
      GROUP BY i.id
      ORDER BY CASE WHEN i.barcode = ? COLLATE NOCASE THEN 0 ELSE 1 END
      LIMIT 1
      ''',
      [term, term, term],
    );
    if (rows.isEmpty) return null;
    return _itemFromAggregateRow(rows.first);
  }

  /// The item's master fields + per-bin on-hand for the detail view, built
  /// entirely from local tables. Returns `null` when the item is not in the
  /// local cache (the offline-first equivalent of a "not found" — it isn't in
  /// the accessible/synced scope). Movement history is intentionally absent
  /// (`InventoryTransactions` sync is out of scope) — the caller renders that
  /// section as empty.
  Future<InventoryItemDetail?> getItemById(String id) async {
    final db = await _db.instance;
    final itemRows = await db.query(
      _item,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (itemRows.isEmpty) return null;
    final item = itemRows.first;

    final stockRows = await db.query(
      _cache,
      where: 'inventory_item_id = ?',
      whereArgs: [id],
    );
    final bins = stockRows
        .map((r) => StockByBin(
              binId: r['bin_id'] as String,
              quantityOnHand: (r['quantity_on_hand'] as num).toDouble(),
              version: r['version'] as int,
            ))
        .toList()
      ..sort((a, b) => a.binId.compareTo(b.binId));

    final total = bins.fold<double>(0, (sum, b) => sum + b.quantityOnHand);

    return InventoryItemDetail(
      id: item['id'] as String,
      sku: item['sku'] as String,
      name: item['name'] as String,
      isActive: (item['is_active'] as int) != 0,
      totalQuantityOnHand: total,
      stockByBin: bins,
      movements: const [],
      companyId: item['company_id'] as String?,
      barcode: item['barcode'] as String?,
      description: item['description'] as String?,
      unitOfMeasure: item['unit_of_measure'] as String?,
      category: item['category'] as String?,
    );
  }

  /// Count of **active** cached items (`is_active = 1`) — the dashboard's
  /// "Total SKUs" tile. A plain local aggregate (no join), no API call.
  Future<int> countActiveItems() async {
    final db = await _db.instance;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_item WHERE is_active = 1',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  // ---- Sync upserts ---------------------------------------------------------

  /// Upserts one page of rows into [table] and, in the **same transaction**,
  /// advances the stored cursor for [entity] — but only when [nextCursor] is
  /// non-null (an empty page's `null` cursor must never overwrite a good stored
  /// cursor). Mirrors `HierarchyLocalDataSource.upsertPageAndAdvanceCursor`.
  Future<void> upsertPageAndAdvanceCursor({
    required String table,
    required String entity,
    required List<Map<String, Object?>> rows,
    required String? nextCursor,
  }) async {
    final db = await _db.instance;
    await db.transaction((txn) async {
      if (rows.isNotEmpty) {
        final batch = txn.batch();
        for (final row in rows) {
          batch.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
      if (nextCursor != null) {
        await txn.update(
          'sync_metadata',
          {'last_cursor': nextCursor},
          where: 'entity = ?',
          whereArgs: [entity],
        );
      }
    });
  }

  // ---- Sync metadata --------------------------------------------------------

  Future<SyncMetadata?> readSyncMetadata(String entity) async {
    final db = await _db.instance;
    final rows = await db.query(
      'sync_metadata',
      where: 'entity = ?',
      whereArgs: [entity],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncMetadata.fromRow(rows.first);
  }

  Future<void> writeSyncMetadata(SyncMetadata meta) async {
    final db = await _db.instance;
    await db.insert(
      'sync_metadata',
      meta.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---- Inventory reachable snapshot ----------------------------------------

  Future<Set<String>> readReachableSnapshot() async {
    final db = await _db.instance;
    final rows = await db.query('inventory_reachable_snapshot');
    return rows.map((r) => r['company_id'] as String).toSet();
  }

  /// Replaces the persisted inventory reachability snapshot atomically.
  Future<void> replaceReachableSnapshot(Set<String> companyIds) async {
    final db = await _db.instance;
    await db.transaction((txn) async {
      await txn.delete('inventory_reachable_snapshot');
      if (companyIds.isNotEmpty) {
        final batch = txn.batch();
        for (final id in companyIds) {
          batch.insert('inventory_reachable_snapshot', {'company_id': id});
        }
        await batch.commit(noResult: true);
      }
    });
  }
}
