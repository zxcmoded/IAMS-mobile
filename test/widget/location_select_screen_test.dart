import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/core/router/app_routes.dart';
import 'package:iams_mobile/features/access/data/scope_repository.dart';
import 'package:iams_mobile/features/access/presentation/controller/selected_location_controller.dart';
import 'package:iams_mobile/features/access/presentation/location_select/location_select_cubit.dart';
import 'package:iams_mobile/features/access/presentation/location_select/location_select_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../support/access_fixtures.dart';

class MockScopeRepository extends Mock implements ScopeRepository {}

void main() {
  late MockScopeRepository scopeRepo;
  late SelectedLocationController controller;

  setUp(() {
    scopeRepo = MockScopeRepository();
    controller = buildSelectedLocationController();
    sl.registerFactory<LocationSelectCubit>(
        () => LocationSelectCubit(scopeRepo));
    sl.registerLazySingleton<SelectedLocationController>(() => controller);
  });

  tearDown(() => sl.reset());

  testWidgets('lists the assigned locations with a disabled Continue',
      (tester) async {
    when(() => scopeRepo.loadScope()).thenAnswer(
        (_) async => scope(locations: [locRef('l1', name: 'Warehouse A')]));

    await tester.pumpWidget(const MaterialApp(home: LocationSelectScreen()));
    await tester.pump(); // resolve load()

    expect(find.text('Warehouse A'), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.byKey(const Key('location_select_continue')));
    expect(button.onPressed, isNull); // nothing selected yet
  });

  testWidgets('choosing a location enables Continue', (tester) async {
    when(() => scopeRepo.loadScope()).thenAnswer((_) async =>
        scope(locations: [locRef('l1', name: 'A'), locRef('l2', name: 'B')]));

    await tester.pumpWidget(const MaterialApp(home: LocationSelectScreen()));
    await tester.pump();

    await tester.tap(find.byKey(const Key('location_option_l2')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
        find.byKey(const Key('location_select_continue')));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('offline shows the explicit offline message and a Retry',
      (tester) async {
    when(() => scopeRepo.loadScope()).thenThrow(const ApiException(
      code: ApiErrorCode.network,
      message: 'mock message from backend',
    ));

    await tester.pumpWidget(const MaterialApp(home: LocationSelectScreen()));
    await tester.pump();

    expect(find.byKey(const Key('location_select_error_message')),
        findsOneWidget);
    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('no assigned locations shows the contact-admin state',
      (tester) async {
    when(() => scopeRepo.loadScope())
        .thenAnswer((_) async => scope(locations: []));

    await tester.pumpWidget(const MaterialApp(home: LocationSelectScreen()));
    await tester.pump();

    expect(find.text('No locations assigned'), findsOneWidget);
    expect(find.byKey(const Key('location_select_continue')), findsNothing);
  });

  testWidgets('Continue persists the selection and navigates to Home',
      (tester) async {
    when(() => scopeRepo.loadScope()).thenAnswer(
        (_) async => scope(locations: [locRef('l1', name: 'Warehouse A')]));

    final router = GoRouter(
      initialLocation: AppRoutes.locationSelect,
      routes: [
        GoRoute(
          path: AppRoutes.locationSelect,
          builder: (_, _) => const LocationSelectScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(); // resolve load()

    await tester.tap(find.byKey(const Key('location_option_l1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('location_select_continue')));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
    expect(controller.currentLocationId, 'l1'); // persisted through the store
  });
}
