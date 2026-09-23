import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import 'models/bin.dart';
import 'models/company.dart';
import 'models/location.dart';
import 'models/rack.dart';
import 'models/sync_metadata.dart';
import 'models/warehouse.dart';

/// The single gateway to the local SQLite store — no SQLite access happens
/// anywhere else. Level reads use the indexed FK columns directly
/// (`WHERE company_id = ?`, etc.), never `SELECT *` then filter in Dart. Page
/// upserts and cursor advancement are done transactionally so a crash can't
/// leave committed rows with a stale cursor.
class HierarchyLocalDataSource {
  HierarchyLocalDataSource(this._db);

  final AppDatabase _db;

  // ---- Level reads (indexed, ordered by name for stable UI listing) --------

  Future<List<Company>> getCompanies() async {
    final db = await _db.instance;
    final rows = await db.query('company', orderBy: 'name COLLATE NOCASE');
    return rows.map(Company.fromRow).toList(growable: false);
  }

  Future<List<Location>> getLocations({required String companyId}) async {
    final db = await _db.instance;
    final rows = await db.query(
      'location',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Location.fromRow).toList(growable: false);
  }

  /// A single location by id (indexed PK lookup), or `null` when it is not in
  /// the local cache — used by the dashboard to resolve the persisted
  /// current-location id to a display name without a network call.
  Future<Location?> getLocationById(String id) async {
    final db = await _db.instance;
    final rows = await db.query(
      'location',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Location.fromRow(rows.first);
  }

  Future<List<Warehouse>> getWarehouses({required String locationId}) async {
    final db = await _db.instance;
    final rows = await db.query(
      'warehouse',
      where: 'location_id = ?',
      whereArgs: [locationId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Warehouse.fromRow).toList(growable: false);
  }

  Future<List<Rack>> getRacks({required String warehouseId}) async {
    final db = await _db.instance;
    final rows = await db.query(
      'rack',
      where: 'warehouse_id = ?',
      whereArgs: [warehouseId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Rack.fromRow).toList(growable: false);
  }

  Future<List<Bin>> getBins({required String rackId}) async {
    final db = await _db.instance;
    final rows = await db.query(
      'bin',
      where: 'rack_id = ?',
      whereArgs: [rackId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Bin.fromRow).toList(growable: false);
  }

  // ---- Page upsert ----------------------------------------------------------

  /// Upserts one page of rows into [table] in a single transaction/batch.
  /// Soft-deleted rows (`is_active = 0`) are upserted like any other — never
  /// deleted — preserving FK integrity for already-synced children.
  Future<void> upsertPage(String table, List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final db = await _db.instance;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(
          table,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Upserts a page and, in the **same transaction**, advances the stored
  /// cursor for [entity] — but only when [nextCursor] is non-null (an empty
  /// page's `null` cursor must never overwrite a good stored cursor). Keeping
  /// the row write and cursor advance atomic means there is no crash window in
  /// which committed rows and their resume cursor disagree.
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

  // ---- Reachable-company snapshot ------------------------------------------

  Future<Set<String>> readReachableSnapshot() async {
    final db = await _db.instance;
    final rows = await db.query('reachable_company_snapshot');
    return rows.map((r) => r['company_id'] as String).toSet();
  }

  /// Replaces the persisted snapshot with [companyIds] atomically.
  Future<void> replaceReachableSnapshot(Set<String> companyIds) async {
    final db = await _db.instance;
    await db.transaction((txn) async {
      await txn.delete('reachable_company_snapshot');
      if (companyIds.isNotEmpty) {
        final batch = txn.batch();
        for (final id in companyIds) {
          batch.insert('reachable_company_snapshot', {'company_id': id});
        }
        await batch.commit(noResult: true);
      }
    });
  }
}
