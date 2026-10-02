import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/connectivity_checker.dart';
import 'package:iams_mobile/core/sync/sync_coordinator.dart';
import 'package:iams_mobile/features/access/presentation/controller/selected_location_controller.dart';
import 'package:iams_mobile/features/access/presentation/home/dashboard_cubit.dart';
import 'package:iams_mobile/features/auth/data/auth_repository.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_controller.dart';
import 'package:iams_mobile/features/inventory/data/inventory_repository.dart';
import 'package:iams_mobile/features/inventory/data/inventory_sync_service.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/outbox_entry.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_repository.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_sync_service.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/access_fixtures.dart';
import '../../support/fixtures.dart';
import '../../support/inventory_fixtures.dart';
import '../../support/masterdata_fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockHierarchySyncService extends Mock implements HierarchySyncService {}

class MockInventorySyncService extends Mock implements InventorySyncService {}

/// A [ConnectivityChecker] whose answer the test controls (mirrors the one in
/// sync_coordinator_test.dart — kept local since only `true` is needed here).
class FakeConnectivity implements ConnectivityChecker {
  FakeConnectivity(this.online);
  bool online;
  @override
  Future<bool> isOnline() async => online;
}

/// The dashboard is offline-first: every field comes from local SQLite. These
/// tests drive it through fakes only (no network, no real DB).
void main() {
  late FakeHierarchyLocalDataSource hierarchyLocal;
  late FakeInventoryLocalDataSource invLocal;
  late FakeOutboxLocalDataSource outbox;
  late HierarchyRepository hierarchy;
  late InventoryRepository inventory;
  late SelectedLocationController selectedLocation;
  late SyncCoordinator syncCoordinator;
  late MockHierarchySyncService hierarchySync;
  late MockInventorySyncService inventorySync;

  setUp(() {
    hierarchyLocal = FakeHierarchyLocalDataSource();
    invLocal = FakeInventoryLocalDataSource();
    outbox = FakeOutboxLocalDataSource();
    hierarchy = HierarchyRepository(hierarchyLocal);
    inventory = InventoryRepository(invLocal, outbox);
    selectedLocation = buildSelectedLocationController();

    hierarchySync = MockHierarchySyncService();
    inventorySync = MockInventorySyncService();
    when(() => hierarchySync.run()).thenAnswer((_) async {});
    when(() => inventorySync.run()).thenAnswer((_) async {});
    syncCoordinator = SyncCoordinator(
      auth: AuthController(
        repository: MockAuthRepository(),
        tokenStore: FakeTokenStore(),
        rememberedKeyStore: FakeRememberedActivationKeyStore(),
      ),
      connectivity: FakeConnectivity(true),
      hierarchySync: hierarchySync,
      inventorySync: inventorySync,
    );
  });

  OutboxEntry pendingFor(String itemId) => OutboxEntry(
        idempotencyKey: 'k-$itemId',
        kind: MutationKind.receive,
        inventoryItemId: itemId,
        payload: const {'destinationBinId': 'b1', 'quantity': 1},
        status: OutboxStatus.pending,
        createdAtUtc: DateTime.utc(2026, 1, 1),
      );

  DashboardCubit build() => DashboardCubit(
        selectedLocation: selectedLocation,
        hierarchy: hierarchy,
        inventory: inventory,
        syncCoordinator: syncCoordinator,
      );

  test('renders company, current location, and summary from local data',
      () async {
    hierarchyLocal.seedRow('company', company('co1', name: 'Acme').toRow());
    hierarchyLocal.seedRow(
        'location', location('l1', companyId: 'co1', name: 'Warehouse A').toRow());
    invLocal.seedItem(itemSync('i1', sku: 'A'));
    invLocal.seedItem(itemSync('i2', sku: 'B'));
    await selectedLocation.select('l1');

    final cubit = build();
    addTearDown(cubit.close);
    await cubit.load();

    expect(cubit.state.status, DashboardStatus.loaded);
    expect(cubit.state.companyName, 'Acme');
    expect(cubit.state.locationName, 'Warehouse A');
    expect(cubit.state.summary.totalSkus, 2);
    expect(cubit.state.summary.syncedCount, 2);
    expect(cubit.state.summary.unsyncedCount, 0);
  });

  test('picks the company matching the current location when several exist',
      () async {
    hierarchyLocal.seedRow('company', company('co1', name: 'Acme').toRow());
    hierarchyLocal.seedRow('company', company('co2', name: 'Globex').toRow());
    hierarchyLocal.seedRow(
        'location', location('l9', companyId: 'co2', name: 'Depot').toRow());
    await selectedLocation.select('l9');

    final cubit = build();
    addTearDown(cubit.close);
    await cubit.load();

    expect(cubit.state.companyName, 'Globex'); // co2, not the first company
    expect(cubit.state.locationName, 'Depot');
  });

  test('unresolved location id leaves the name null (still renders)', () async {
    hierarchyLocal.seedRow('company', company('co1', name: 'Acme').toRow());
    await selectedLocation.select('not-synced-yet');

    final cubit = build();
    addTearDown(cubit.close);
    await cubit.load();

    expect(cubit.state.status, DashboardStatus.loaded);
    expect(cubit.state.locationName, isNull);
    expect(cubit.state.companyName, 'Acme'); // falls back to first company
  });

  test('an item with a pending mutation is reported as offline/unsynced',
      () async {
    invLocal.seedItem(itemSync('i1', sku: 'A'));
    invLocal.seedItem(itemSync('i2', sku: 'B'));
    await outbox.insertOutbox(pendingFor('i1'));
    await selectedLocation.load();

    final cubit = build();
    addTearDown(cubit.close);
    await cubit.load();

    expect(cubit.state.summary.totalSkus, 2);
    expect(cubit.state.summary.unsyncedCount, 1);
    expect(cubit.state.summary.syncedCount, 1);
  });

  test('reloads automatically when the current-location selection changes',
      () async {
    hierarchyLocal.seedRow(
        'location', location('l1', companyId: 'co1', name: 'Warehouse A').toRow());
    hierarchyLocal.seedRow(
        'location', location('l2', companyId: 'co1', name: 'Warehouse B').toRow());
    await selectedLocation.select('l1');

    final cubit = build();
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.locationName, 'Warehouse A');

    // Changing the selection should push a fresh loaded state naming l2. Set up
    // the expectation, then trigger, then await it (triggering before awaiting
    // avoids a deadlock).
    final reloaded = expectLater(
      cubit.stream,
      emitsThrough(predicate<DashboardState>((s) =>
          s.status == DashboardStatus.loaded &&
          s.locationName == 'Warehouse B')),
    );
    await selectedLocation.select('l2');
    await reloaded;
  });

  test(
      'reloads automatically when a background sync pass completes, picking '
      'up a location name that was not yet in the local cache at first load',
      () async {
    // Mirrors the real first-activation race: the location isn't in the
    // local hierarchy cache yet when the dashboard first loads, because the
    // headless background sync (SyncCoordinator) hasn't pulled it down.
    await selectedLocation.select('l1');

    final cubit = build();
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.status, DashboardStatus.loaded);
    expect(cubit.state.locationName, isNull); // placeholder-worthy: not synced yet

    // The background sync "lands" the location locally...
    hierarchyLocal.seedRow(
        'location', location('l1', companyId: 'co1', name: 'Warehouse A').toRow());

    // ...then the coordinator signals the pass completed. The dashboard must
    // self-correct without a manual pull-to-refresh. Set up the expectation
    // before triggering, then await it, to avoid a deadlock.
    final reloaded = expectLater(
      cubit.stream,
      emitsThrough(predicate<DashboardState>((s) =>
          s.status == DashboardStatus.loaded &&
          s.locationName == 'Warehouse A')),
    );
    await syncCoordinator.triggerBackgroundSync();
    await reloaded;
  });
}
