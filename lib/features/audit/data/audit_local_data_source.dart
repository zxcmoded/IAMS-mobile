import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import 'models/audit_record.dart';

/// The SQLite gateway for the fully-offline **Audit** store (`audit_record`).
/// All SQL for this feature lives here and nowhere else. It holds no API client —
/// nothing in this class can reach the network, so audit data is durably local
/// by construction (the same guarantee the inventory read repositories give).
class AuditLocalDataSource {
  AuditLocalDataSource(this._db);

  final AppDatabase _db;

  static const _table = 'audit_record';

  /// Inserts a batch of validated audit rows in a single transaction, so a crash
  /// mid-import can never leave a partially-written set. Appends to whatever is
  /// already stored (import is additive, not a replace).
  Future<void> insertRecords(List<AuditRecord> records) async {
    if (records.isEmpty) return;
    final db = await _db.instance;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final record in records) {
        batch.insert(
          _table,
          record.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// All stored audit rows, newest first.
  Future<List<AuditRecord>> getRecords() async {
    final db = await _db.instance;
    final rows = await db.query(_table, orderBy: 'created_at_utc DESC');
    return rows.map(AuditRecord.fromRow).toList(growable: false);
  }

  /// Total number of stored audit rows.
  Future<int> count() async {
    final db = await _db.instance;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $_table');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Deletes every stored audit row. Used by the "Clear" action so a fresh
  /// import isn't mixed with stale data.
  Future<void> deleteAll() async {
    final db = await _db.instance;
    await db.delete(_table);
  }
}
