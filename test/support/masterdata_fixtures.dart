import 'package:iams_mobile/features/masterdata/data/hierarchy_local_data_source.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_sync_service.dart';
import 'package:iams_mobile/features/masterdata/data/models/bin.dart';
import 'package:iams_mobile/features/masterdata/data/models/company.dart';
import 'package:iams_mobile/features/masterdata/data/models/location.dart';
import 'package:iams_mobile/features/masterdata/data/models/master_data_page.dart';
import 'package:iams_mobile/features/masterdata/data/models/rack.dart';
import 'package:iams_mobile/features/masterdata/data/models/sync_metadata.dart';
import 'package:iams_mobile/features/masterdata/data/models/warehouse.dart';

final _t0 = DateTime.utc(2026, 1, 1);

Company company(String id, {String name = 'Co', bool isActive = true}) =>
    Company(
      id: id,
      tenantId: 'tn1',
      name: name,
      isActive: isActive,
      createdAtUtc: _t0,
    );

Location location(String id,
        {String companyId = 'co1',
        String name = 'Loc',
        bool isActive = true}) =>
    Location(
      id: id,
      tenantId: 'tn1',
      companyId: companyId,
      name: name,
      isActive: isActive,
      createdAtUtc: _t0,
    );

Warehouse warehouse(String id,
        {String locationId = 'l1',
        String companyId = 'co1',
        String name = 'Wh',
        bool isActive = true}) =>
    Warehouse(
      id: id,
      tenantId: 'tn1',
      locationId: locationId,
      companyId: companyId,
      name: name,
      isActive: isActive,
      createdAtUtc: _t0,
    );

Rack rack(String id,
        {String warehouseId = 'w1',
        String locationId = 'l1',
        String companyId = 'co1',
        String name = 'Rk',
        bool isActive = true}) =>
    Rack(
      id: id,
      tenantId: 'tn1',
      warehouseId: warehouseId,
      locationId: locationId,
      companyId: companyId,
      name: name,
      isActive: isActive,
      createdAtUtc: _t0,
    );

Bin bin(String id,
        {String rackId = 'r1',
        String warehouseId = 'w1',
        String locationId = 'l1',
        String companyId = 'co1',
        String name = 'Bn',
        bool isActive = true}) =>
    Bin(
      id: id,
      tenantId: 'tn1',
      rackId: rackId,
      warehouseId: warehouseId,
      locationId: locationId,
      companyId: companyId,
      name: name,
      isActive: isActive,
      createdAtUtc: _t0,
    );

MasterDataPage<T> page<T>(
  List<T> items, {
  String? nextCursor,
  bool hasMore = false,
}) =>
    MasterDataPage<T>(items: items, nextCursor: nextCursor, hasMore: hasMore);

/// In-memory [HierarchyLocalDataSource] that mirrors the real SQLite behaviour
/// the sync engine relies on: id-keyed upsert (replace), one metadata row per
/// entity, and — crucially — cursor advancement **only** from a non-null
/// nextCursor (the empty-page rule). No platform channel / real DB needed.
class FakeHierarchyLocalDataSource implements HierarchyLocalDataSource {
  final Map<String, Map<String, Map<String, Object?>>> _tables = {
    for (final t in SyncLevels.all) t: <String, Map<String, Object?>>{},
  };
  final Map<String, SyncMetadata> _meta = {};
  Set<String> _snapshot = {};

  int reachableReplacements = 0;

  // ---- Test helpers ---------------------------------------------------------

  void seedRow(String table, Map<String, Object?> row) {
    _tables[table]![row['id'] as String] = row;
  }

  void seedMetadata(SyncMetadata meta) => _meta[meta.entity] = meta;

  void seedSnapshot(Set<String> ids) => _snapshot = {...ids};

  int rowCount(String table) => _tables[table]!.length;

  SyncMetadata? metaOf(String entity) => _meta[entity];

  // ---- Level reads ----------------------------------------------------------

  @override
  Future<List<Company>> getCompanies() async =>
      _tables['company']!.values.map(Company.fromRow).toList(growable: false);

  @override
  Future<List<Location>> getLocations({required String companyId}) async =>
      _tables['location']!
          .values
          .where((r) => r['company_id'] == companyId)
          .map(Location.fromRow)
          .toList(growable: false);

  @override
  Future<List<Warehouse>> getWarehouses({required String locationId}) async =>
      _tables['warehouse']!
          .values
          .where((r) => r['location_id'] == locationId)
          .map(Warehouse.fromRow)
          .toList(growable: false);

  @override
  Future<List<Rack>> getRacks({required String warehouseId}) async =>
      _tables['rack']!
          .values
          .where((r) => r['warehouse_id'] == warehouseId)
          .map(Rack.fromRow)
          .toList(growable: false);

  @override
  Future<List<Bin>> getBins({required String rackId}) async => _tables['bin']!
      .values
      .where((r) => r['rack_id'] == rackId)
      .map(Bin.fromRow)
      .toList(growable: false);

  // ---- Upsert ---------------------------------------------------------------

  @override
  Future<void> upsertPage(String table, List<Map<String, Object?>> rows) async {
    for (final row in rows) {
      _tables[table]![row['id'] as String] = row;
    }
  }

  @override
  Future<void> upsertPageAndAdvanceCursor({
    required String table,
    required String entity,
    required List<Map<String, Object?>> rows,
    required String? nextCursor,
  }) async {
    for (final row in rows) {
      _tables[table]![row['id'] as String] = row;
    }
    if (nextCursor != null) {
      final existing = _meta[entity] ?? SyncMetadata(entity: entity);
      _meta[entity] = existing.copyWith(lastCursor: nextCursor);
    }
  }

  // ---- Metadata -------------------------------------------------------------

  @override
  Future<SyncMetadata?> readSyncMetadata(String entity) async => _meta[entity];

  @override
  Future<void> writeSyncMetadata(SyncMetadata meta) async =>
      _meta[meta.entity] = meta;

  // ---- Snapshot -------------------------------------------------------------

  @override
  Future<Set<String>> readReachableSnapshot() async => {..._snapshot};

  @override
  Future<void> replaceReachableSnapshot(Set<String> companyIds) async {
    _snapshot = {...companyIds};
    reachableReplacements++;
  }
}
