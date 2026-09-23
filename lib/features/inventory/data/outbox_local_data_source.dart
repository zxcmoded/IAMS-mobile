import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import 'models/cached_stock_level.dart';
import 'models/inventory_enums.dart';
import 'models/outbox_entry.dart';

/// The single SQLite gateway for the F4 offline-first store — the outbox queue
/// and the stock-version cache. No inventory SQL happens anywhere else (mirrors
/// `HierarchyLocalDataSource`). Reads use the indexed columns directly; the
/// only compound write (reconcile several bins at once) is done in one
/// transaction so a crash can't leave a half-applied reconcile.
class OutboxLocalDataSource {
  OutboxLocalDataSource(this._db);

  final AppDatabase _db;

  static const _outbox = 'outbox_mutation';
  static const _cache = 'stock_version_cache';

  // ---- Outbox ---------------------------------------------------------------

  /// Inserts a new queued mutation. Uses `ConflictAlgorithm.replace`, so
  /// re-committing the *same* [OutboxEntry.idempotencyKey] (the PK) overwrites
  /// rather than erroring — the key is the stable id for one logical mutation.
  Future<void> insertOutbox(OutboxEntry entry) async {
    final db = await _db.instance;
    await db.insert(
      _outbox,
      entry.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Persists a status/attempt/response change to an existing outbox row.
  Future<void> updateOutbox(OutboxEntry entry) async {
    final db = await _db.instance;
    await db.update(
      _outbox,
      entry.toRow(),
      where: 'idempotency_key = ?',
      whereArgs: [entry.idempotencyKey],
    );
  }

  Future<void> deleteOutbox(String idempotencyKey) async {
    final db = await _db.instance;
    await db.delete(
      _outbox,
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
    );
  }

  Future<OutboxEntry?> getOutbox(String idempotencyKey) async {
    final db = await _db.instance;
    final rows = await db.query(
      _outbox,
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OutboxEntry.fromRow(rows.first);
  }

  /// All queued mutations for one item, oldest-first, for the item-detail
  /// "pending sync" section.
  Future<List<OutboxEntry>> getOutboxForItem(String inventoryItemId) async {
    final db = await _db.instance;
    final rows = await db.query(
      _outbox,
      where: 'inventory_item_id = ?',
      whereArgs: [inventoryItemId],
      orderBy: 'created_at_utc ASC, rowid ASC',
    );
    return rows.map(OutboxEntry.fromRow).toList(growable: false);
  }

  /// Pending mutations only, in the exact order they were committed — the queue
  /// the reconnect replay walks so per-bin effects apply in submission order.
  Future<List<OutboxEntry>> getPendingOrdered() async {
    final db = await _db.instance;
    final rows = await db.query(
      _outbox,
      where: 'status = ?',
      whereArgs: [OutboxStatus.pending.wire],
      orderBy: 'created_at_utc ASC, rowid ASC',
    );
    return rows.map(OutboxEntry.fromRow).toList(growable: false);
  }

  /// Every not-yet-synced mutation that should overlay its delta on read — i.e.
  /// `pending` or `conflict` (the same rows the item-detail overlay applies).
  /// Ordered oldest-first for deterministic accumulation. Powers the list
  /// read path's pending overlay so a queued mutation is reflected in the
  /// aggregate on-hand immediately, without waiting for a resync.
  Future<List<OutboxEntry>> getOverlayEntries() async {
    final db = await _db.instance;
    final rows = await db.query(
      _outbox,
      where: 'status IN (?, ?)',
      whereArgs: [OutboxStatus.pending.wire, OutboxStatus.conflict.wire],
      orderBy: 'created_at_utc ASC, rowid ASC',
    );
    return rows.map(OutboxEntry.fromRow).toList(growable: false);
  }

  /// Count of rows in any of [statuses] — powers the badge/summary affordances.
  Future<int> countByStatus(List<OutboxStatus> statuses) async {
    if (statuses.isEmpty) return 0;
    final db = await _db.instance;
    final placeholders = List.filled(statuses.length, '?').join(',');
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_outbox WHERE status IN ($placeholders)',
      statuses.map((s) => s.wire).toList(),
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// The set of distinct inventory item ids that have at least one outbox row in
  /// any of [statuses] — powers the dashboard's "Sync Status" split (an item
  /// with a `pending`/`failed` row counts as offline/unsynced). `DISTINCT` so
  /// several queued mutations on one item collapse to a single unsynced item.
  Future<Set<String>> itemIdsWithStatus(List<OutboxStatus> statuses) async {
    if (statuses.isEmpty) return <String>{};
    final db = await _db.instance;
    final placeholders = List.filled(statuses.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT DISTINCT inventory_item_id FROM $_outbox '
      'WHERE status IN ($placeholders)',
      statuses.map((s) => s.wire).toList(),
    );
    return rows.map((r) => r['inventory_item_id'] as String).toSet();
  }

  // ---- Stock-version cache --------------------------------------------------

  Future<CachedStockLevel?> getStockLevel(
    String inventoryItemId,
    String binId,
  ) async {
    final db = await _db.instance;
    final rows = await db.query(
      _cache,
      where: 'inventory_item_id = ? AND bin_id = ?',
      whereArgs: [inventoryItemId, binId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CachedStockLevel.fromRow(rows.first);
  }

  Future<List<CachedStockLevel>> getStockLevelsForItem(
    String inventoryItemId,
  ) async {
    final db = await _db.instance;
    final rows = await db.query(
      _cache,
      where: 'inventory_item_id = ?',
      whereArgs: [inventoryItemId],
    );
    return rows.map(CachedStockLevel.fromRow).toList(growable: false);
  }

  Future<void> upsertStockLevel(CachedStockLevel level) async {
    final db = await _db.instance;
    await db.insert(
      _cache,
      level.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Upserts several bins' cached levels in one transaction — used when a
  /// mutation response or item-detail fetch reconciles multiple bins at once.
  Future<void> upsertStockLevels(List<CachedStockLevel> levels) async {
    if (levels.isEmpty) return;
    final db = await _db.instance;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final level in levels) {
        batch.insert(
          _cache,
          level.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }
}
