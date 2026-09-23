import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import 'models/inventory_record.dart';

/// The SQLite gateway for the offline-first **Create-Inventory** session store
/// (`inventory_record` + `inventory_record_line`). All SQL for this feature
/// lives here and nowhere else. It holds no API client — nothing in this class
/// can reach the network, so a saved record is durably local by construction.
///
/// A record and its lines are written in a single transaction so a crash can
/// never leave a header with partial lines (or lines with no header).
class InventoryRecordLocalDataSource {
  InventoryRecordLocalDataSource(this._db);

  final AppDatabase _db;

  static const _record = 'inventory_record';
  static const _line = 'inventory_record_line';

  /// Inserts a record header and all its lines atomically. `is_offline` comes
  /// off the model (always `1` on create) — this method never overrides it.
  Future<void> insertRecord(InventoryRecord record) async {
    final db = await _db.instance;
    await db.transaction((txn) async {
      await txn.insert(
        _record,
        record.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (record.items.isNotEmpty) {
        final batch = txn.batch();
        for (final line in record.items) {
          batch.insert(
            _line,
            line.toRow(record.id),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
    });
  }

  /// All saved records, newest first, each with its lines eagerly loaded.
  Future<List<InventoryRecord>> getRecords() async {
    final db = await _db.instance;
    final headerRows = await db.query(_record, orderBy: 'created_at_utc DESC');
    if (headerRows.isEmpty) return const [];

    final lineRows = await db.query(_line);
    final linesByRecord = <String, List<InventoryRecordLine>>{};
    for (final row in lineRows) {
      (linesByRecord[row['record_id'] as String] ??= [])
          .add(InventoryRecordLine.fromRow(row));
    }
    for (final lines in linesByRecord.values) {
      lines.sort((a, b) => a.sku.toLowerCase().compareTo(b.sku.toLowerCase()));
    }

    return headerRows
        .map((h) => InventoryRecord.fromRow(
              h,
              linesByRecord[h['id'] as String] ?? const [],
            ))
        .toList(growable: false);
  }

  /// A single record with its lines, or `null` if not found.
  Future<InventoryRecord?> getRecordById(String id) async {
    final db = await _db.instance;
    final headerRows =
        await db.query(_record, where: 'id = ?', whereArgs: [id], limit: 1);
    if (headerRows.isEmpty) return null;
    final lineRows =
        await db.query(_line, where: 'record_id = ?', whereArgs: [id]);
    final lines = lineRows.map(InventoryRecordLine.fromRow).toList()
      ..sort((a, b) => a.sku.toLowerCase().compareTo(b.sku.toLowerCase()));
    return InventoryRecord.fromRow(headerRows.first, lines);
  }
}
