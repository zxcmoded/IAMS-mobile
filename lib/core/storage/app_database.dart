import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../features/audit/data/audit_schema.dart';
import '../../features/inventory/data/inventory_record_schema.dart';
import '../../features/inventory/data/inventory_schema.dart';
import '../../features/masterdata/data/hierarchy_schema.dart';
import '../../features/masterdata/data/sync_metadata_schema.dart';
import 'app_settings_schema.dart';

/// Owns the app's local SQLite database (`iams.db`) — the offline store for the
/// master-data hierarchy and its sync bookkeeping. Opened lazily and cached, so
/// [instance] is safe to await repeatedly (main() awaits it once up front to
/// surface open/migration failures before the first frame).
///
/// Foreign keys are enforced (`PRAGMA foreign_keys = ON` in [_onConfigure]).
/// All schema DDL lives in the feature's `*_schema.dart` files; this class only
/// opens the file and dispatches create/upgrade.
class AppDatabase {
  AppDatabase({String databaseName = 'iams.db'})
      // ignore: prefer_initializing_formals
      : _databaseName = databaseName;

  static const int _version = 6;

  final String _databaseName;

  Database? _db;
  Future<Database>? _opening;

  /// The opened database, opening it on first access. Concurrent callers share
  /// the same in-flight open future.
  Future<Database> get instance {
    final db = _db;
    if (db != null) return Future.value(db);
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), _databaseName);
    final db = await openDatabase(
      path,
      version: _version,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _db = db;
    return db;
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final statement in [
      ...hierarchySchema,
      ...syncMetadataSchema,
      ...inventorySchema, // v2 — F4 offline-first outbox + stock cache
      ...inventoryMasterSchema, // v3 — offline-first inventory read cache
      ...appSettingsSchema, // v4 — local settings (current-location selection)
      ...inventoryRecordSchema, // v5 — offline-first Create-Inventory sessions
      ...auditSchema, // v6 — fully-offline Audit import/export table
    ]) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  /// Incremental upgrades. Each `case` is the version being upgraded *from* and
  /// falls through (`continue`) so a device several versions behind runs every
  /// intervening migration in order.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    final batch = db.batch();
    switch (oldVersion) {
      case 1:
        // v1 → v2: add the Phase-2a inventory outbox + stock-version cache.
        for (final statement in inventorySchema) {
          batch.execute(statement);
        }
        continue v2;
      v2:
      case 2:
        // v2 → v3: add the offline-first inventory read cache (inventory_item
        // master table + inventory reachability snapshot).
        for (final statement in inventoryMasterSchema) {
          batch.execute(statement);
        }
        continue v3;
      v3:
      case 3:
        // v3 → v4: add the app-wide local settings key/value table (holds the
        // current-location selection persisted after activation).
        for (final statement in appSettingsSchema) {
          batch.execute(statement);
        }
        continue v4;
      v4:
      case 4:
        // v4 → v5: add the offline-first Create-Inventory session tables
        // (inventory_record header + inventory_record_line lines).
        for (final statement in inventoryRecordSchema) {
          batch.execute(statement);
        }
        continue v5;
      v5:
      case 5:
        // v5 → v6: add the fully-offline Audit import/export table.
        for (final statement in auditSchema) {
          batch.execute(statement);
        }
        continue v6;
      v6:
      case 6:
        break;
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }
}
