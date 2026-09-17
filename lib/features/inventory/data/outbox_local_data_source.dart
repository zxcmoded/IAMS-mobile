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
