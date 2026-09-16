import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_repository.dart';

import '../../support/masterdata_fixtures.dart';

/// The repository is constructed with **only** a local data source — there is
/// no `HierarchyApi` field to inject, so it is structurally incapable of
/// reaching the network. These tests confirm each getter reads local rows and
/// scopes by the correct parent id.
void main() {
  late FakeHierarchyLocalDataSource local;
  late HierarchyRepository repo;

  setUp(() {
    local = FakeHierarchyLocalDataSource();
    repo = HierarchyRepository(local);
  });

  test('getCompanies reads all local company rows', () async {
    local.seedRow('company', company('co1', name: 'Acme').toRow());
    local.seedRow('company', company('co2', name: 'Globex').toRow());

    final result = await repo.getCompanies();

    expect(result.map((c) => c.id), containsAll(['co1', 'co2']));
  });

  test('getLocations scopes to the given companyId', () async {
    local.seedRow('location', location('l1', companyId: 'co1').toRow());
    local.seedRow('location', location('l2', companyId: 'co1').toRow());
    local.seedRow('location', location('l3', companyId: 'co2').toRow());

    final result = await repo.getLocations('co1');

    expect(result.map((l) => l.id), unorderedEquals(['l1', 'l2']));
  });

  test('getWarehouses scopes to the given locationId', () async {
    local.seedRow('warehouse', warehouse('w1', locationId: 'l1').toRow());
    local.seedRow('warehouse', warehouse('w2', locationId: 'l9').toRow());

    final result = await repo.getWarehouses('l1');

    expect(result.map((w) => w.id), ['w1']);
  });

  test('getRacks scopes to the given warehouseId', () async {
    local.seedRow('rack', rack('r1', warehouseId: 'w1').toRow());
    local.seedRow('rack', rack('r2', warehouseId: 'w2').toRow());

    final result = await repo.getRacks('w1');

    expect(result.map((r) => r.id), ['r1']);
  });

  test('getBins scopes to the given rackId and preserves isActive=false',
      () async {
    local.seedRow('bin', bin('b1', rackId: 'r1', isActive: false).toRow());
    local.seedRow('bin', bin('b2', rackId: 'r2').toRow());

    final result = await repo.getBins('r1');

    expect(result.map((b) => b.id), ['b1']);
    expect(result.single.isActive, isFalse);
  });
}
