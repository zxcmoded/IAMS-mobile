import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../features/masterdata/data/hierarchy_schema.dart';
import '../../features/masterdata/data/sync_metadata_schema.dart';

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

  static const int _version = 1;

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
    for (final statement in [...hierarchySchema, ...syncMetadataSchema]) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  /// No migrations exist yet (v1 is the only version). The empty `switch`
  /// stands ready for future incremental upgrades — each future version adds a
  /// fall-through `case` here.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    switch (oldVersion) {
      // case 1: await db.execute('...'); continue; // future v2 migration
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }
}
