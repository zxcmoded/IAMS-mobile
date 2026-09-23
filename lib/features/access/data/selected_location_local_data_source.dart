import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';

/// The SQLite gateway for the persisted **current-location selection** — the one
/// location the user chose to operate within after activation. Stored as a
/// single row in the generic `app_setting` key/value table (schema v4) under the
/// [_key] key. No other code touches this table for this concern (mirrors the
/// single-gateway rule the other data sources follow).
///
/// Not in `flutter_secure_storage` — that is reserved for the auth token. This
/// is plain, non-sensitive UI state.
class SelectedLocationLocalDataSource {
  SelectedLocationLocalDataSource(this._db);

  final AppDatabase _db;

  static const _table = 'app_setting';
  static const _key = 'selected_location_id';

  /// The persisted location id, or `null` when the user has not yet made a
  /// selection (the signal the router uses to show the one-time gate).
  Future<String?> read() async {
    final db = await _db.instance;
    final rows = await db.query(
      _table,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  /// Persists (or replaces) the selected location id.
  Future<void> write(String locationId) async {
    final db = await _db.instance;
    await db.insert(
      _table,
      {'key': _key, 'value': locationId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes the selection so the next launch re-shows the one-time gate — used
  /// on the "forget this device" hand-off.
  Future<void> clear() async {
    final db = await _db.instance;
    await db.delete(_table, where: 'key = ?', whereArgs: [_key]);
  }
}
