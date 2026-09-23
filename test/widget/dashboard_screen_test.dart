import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/features/access/presentation/controller/selected_location_controller.dart';
import 'package:iams_mobile/features/access/presentation/home/dashboard_cubit.dart';
import 'package:iams_mobile/features/access/presentation/home/home_screen.dart';
import 'package:iams_mobile/features/auth/data/auth_repository.dart';
import 'package:iams_mobile/features/auth/data/models/auth_session.dart';
import 'package:iams_mobile/features/auth/data/models/auth_user.dart';
import 'package:iams_mobile/features/auth/data/models/role.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_controller.dart';
import 'package:iams_mobile/features/inventory/data/inventory_repository.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../support/access_fixtures.dart';
import '../support/fixtures.dart';
import '../support/inventory_fixtures.dart';
import '../support/masterdata_fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

AuthSession _sessionWithRole(Role role) => AuthSession(
      accessToken: 'a',
      tokenType: 'Bearer',
      accessTokenExpiresAt: DateTime.utc(2126, 1, 1),
      user: AuthUser(
        id: 'u1',
        username: 'alice',
        displayName: 'Alice',
        companyId: 'co1',
        role: role,
      ),
    );

void main() {
  late FakeHierarchyLocalDataSource hierarchyLocal;
  late FakeInventoryLocalDataSource invLocal;
  late FakeOutboxLocalDataSource outbox;
  late SelectedLocationController controller;
  late AuthController auth;

  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(); // create + load()
    await tester.pump(); // resolve the local reads
  }

  setUp(() async {
    hierarchyLocal = FakeHierarchyLocalDataSource();
    invLocal = FakeInventoryLocalDataSource();
    outbox = FakeOutboxLocalDataSource();

    hierarchyLocal.seedRow('company', company('co1', name: 'Acme').toRow());
    hierarchyLocal.seedRow('location',
        location('l1', companyId: 'co1', name: 'Warehouse A').toRow());
    invLocal.seedItem(itemSync('i1', sku: 'A'));
    invLocal.seedItem(itemSync('i2', sku: 'B'));

    controller = buildSelectedLocationController(initial: 'l1');
    await controller.load();

    auth = AuthController(
      repository: MockAuthRepository(),
      tokenStore: FakeTokenStore(),
      rememberedKeyStore: FakeRememberedActivationKeyStore(),
    );
    await auth.onAuthenticated(_sessionWithRole(Role.manager));

    sl.registerFactory<DashboardCubit>(() => DashboardCubit(
          selectedLocation: controller,
          hierarchy: HierarchyRepository(hierarchyLocal),
          inventory: InventoryRepository(invLocal, outbox),
        ));
    sl.registerLazySingleton<AuthController>(() => auth);
    sl.registerLazySingleton<SelectedLocationController>(() => controller);
  });

  tearDown(() {
    auth.close();
    sl.reset();
  });

  testWidgets('shows the company card with name, user, and role badge',
      (tester) async {
    await pumpDashboard(tester);

    expect(find.byKey(const Key('dashboard_company_card')), findsOneWidget);
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Manager'), findsOneWidget); // role badge
  });

  testWidgets('shows the current-location card with a Change action',
      (tester) async {
    await pumpDashboard(tester);

    expect(find.byKey(const Key('dashboard_location_card')), findsOneWidget);
    expect(find.text('Warehouse A'), findsOneWidget);
    expect(find.byKey(const Key('dashboard_change_location')), findsOneWidget);
  });

  testWidgets('shows the inventory summary tiles from local counts',
      (tester) async {
    await pumpDashboard(tester);

    expect(find.byKey(const Key('dashboard_total_skus')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_sync_status')), findsOneWidget);
    // 2 active SKUs, both synced (no pending/failed outbox rows).
    expect(find.text('2'), findsOneWidget); // Total SKUs
    expect(find.text('2 synced'), findsOneWidget);
    expect(find.text('0 offline'), findsOneWidget);
  });

  testWidgets('the old "assigned locations list" section is gone',
      (tester) async {
    await pumpDashboard(tester);

    expect(find.text('Assigned locations'), findsNothing);
  });

  testWidgets('keeps the sign-out affordance', (tester) async {
    await pumpDashboard(tester);

    expect(find.byKey(const Key('home_sign_out')), findsOneWidget);
  });
}
