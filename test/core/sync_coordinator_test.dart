import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/connectivity_checker.dart';
import 'package:iams_mobile/core/sync/sync_coordinator.dart';
import 'package:iams_mobile/features/auth/data/auth_repository.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_controller.dart';
import 'package:iams_mobile/features/inventory/data/inventory_sync_service.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_sync_service.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fixtures.dart';

class MockHierarchySyncService extends Mock implements HierarchySyncService {}

class MockInventorySyncService extends Mock implements InventorySyncService {}

class MockAuthRepository extends Mock implements AuthRepository {}

/// A [ConnectivityChecker] whose answer the test controls.
class FakeConnectivity implements ConnectivityChecker {
  FakeConnectivity(this.online);
  bool online;
  int checks = 0;
  @override
  Future<bool> isOnline() async {
    checks++;
    return online;
  }
}

void main() {
  late MockHierarchySyncService hierarchy;
  late MockInventorySyncService inventory;

  setUp(() {
    hierarchy = MockHierarchySyncService();
    inventory = MockInventorySyncService();
    when(() => hierarchy.run()).thenAnswer((_) async {});
    when(() => inventory.run()).thenAnswer((_) async {});
  });

  AuthController authController() => AuthController(
        repository: MockAuthRepository(),
        tokenStore: FakeTokenStore(),
        rememberedKeyStore: FakeRememberedActivationKeyStore(),
      );

  SyncCoordinator build(AuthController auth, ConnectivityChecker conn) =>
      SyncCoordinator(
        auth: auth,
        connectivity: conn,
        hierarchySync: hierarchy,
        inventorySync: inventory,
      );

  group('triggerBackgroundSync', () {
    test('offline → skips both syncs silently', () async {
      final conn = FakeConnectivity(false);
      final coordinator = build(authController(), conn);

      await coordinator.triggerBackgroundSync();

      expect(conn.checks, 1);
      verifyNever(() => hierarchy.run());
      verifyNever(() => inventory.run());
    });

    test('online → runs both hierarchy and inventory sync', () async {
      final coordinator = build(authController(), FakeConnectivity(true));

      await coordinator.triggerBackgroundSync();

      verify(() => hierarchy.run()).called(1);
      verify(() => inventory.run()).called(1);
    });

    test('a failing sync is swallowed and does not abort the other', () async {
      when(() => hierarchy.run()).thenThrow(Exception('boom'));
      final coordinator = build(authController(), FakeConnectivity(true));

      // Must not throw.
      await coordinator.triggerBackgroundSync();

      verify(() => hierarchy.run()).called(1);
      verify(() => inventory.run()).called(1);
    });

    test('re-entrant trigger while a pass is in flight is a no-op', () async {
      final gate = Completer<void>();
      when(() => hierarchy.run()).thenAnswer((_) => gate.future);
      when(() => inventory.run()).thenAnswer((_) => gate.future);
      final coordinator = build(authController(), FakeConnectivity(true));

      final first = coordinator.triggerBackgroundSync();
      await Future<void>.delayed(Duration.zero); // let the pass start
      await coordinator.triggerBackgroundSync(); // should short-circuit
      gate.complete();
      await first;

      verify(() => hierarchy.run()).called(1);
      verify(() => inventory.run()).called(1);
    });
  });

  group('start', () {
    test('an already-authenticated session triggers an initial pass', () async {
      final auth = authController();
      await auth.onAuthenticated(buildSession());
      final coordinator = build(auth, FakeConnectivity(true));

      coordinator.start();
      await Future<void>.delayed(Duration.zero);

      verify(() => hierarchy.run()).called(1);
      verify(() => inventory.run()).called(1);
      await coordinator.dispose();
    });

    test('an unauthenticated session does not trigger until activation',
        () async {
      final auth = authController();
      await auth.bootstrap(); // → unauthenticated
      final coordinator = build(auth, FakeConnectivity(true));

      coordinator.start();
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => hierarchy.run());

      // A later activation transition fires the sync.
      await auth.onAuthenticated(buildSession());
      await Future<void>.delayed(Duration.zero);
      verify(() => hierarchy.run()).called(1);
      verify(() => inventory.run()).called(1);
      await coordinator.dispose();
    });
  });
}
