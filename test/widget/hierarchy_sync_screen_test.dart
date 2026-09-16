import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/core/router/app_routes.dart';
import 'package:iams_mobile/features/masterdata/presentation/sync/hierarchy_sync_cubit.dart';
import 'package:iams_mobile/features/masterdata/presentation/sync/hierarchy_sync_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockHierarchySyncCubit extends MockCubit<HierarchySyncState>
    implements HierarchySyncCubit {}

void main() {
  late MockHierarchySyncCubit cubit;

  setUp(() {
    cubit = MockHierarchySyncCubit();
    when(() => cubit.checkAndSync()).thenAnswer((_) async {});
    when(() => cubit.retry()).thenAnswer((_) async {});
    if (sl.isRegistered<HierarchySyncCubit>()) {
      sl.unregister<HierarchySyncCubit>();
    }
    sl.registerFactory<HierarchySyncCubit>(() => cubit);
  });

  tearDown(() => sl.reset());

  Future<void> pumpRouted(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.sync,
      routes: [
        GoRoute(
          path: AppRoutes.sync,
          builder: (_, _) => const HierarchySyncScreen(),
        ),
        GoRoute(
          path: AppRoutes.companies,
          builder: (_, _) => const Scaffold(body: Text('COMPANIES')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
  }

  testWidgets('checking → shows the checking status line', (tester) async {
    whenListen(
      cubit,
      const Stream<HierarchySyncState>.empty(),
      initialState: const HierarchySyncState(stage: SyncStage.checking),
    );

    await pumpRouted(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Checking'), findsOneWidget);
  });

  testWidgets('syncing → shows the per-level progress label', (tester) async {
    whenListen(
      cubit,
      const Stream<HierarchySyncState>.empty(),
      initialState: const HierarchySyncState(
        stage: SyncStage.syncing,
        level: 'warehouse',
      ),
    );

    await pumpRouted(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('warehouses'), findsOneWidget);
  });

  testWidgets('retryable error → shows retry, taps call retry()',
      (tester) async {
    whenListen(
      cubit,
      const Stream<HierarchySyncState>.empty(),
      initialState: const HierarchySyncState(
        stage: SyncStage.error,
        errorCode: 'network_error',
        errorMessage: 'offline',
        retryable: true,
      ),
    );

    await pumpRouted(tester);

    expect(find.text('offline'), findsOneWidget);
    final retry = find.byKey(const Key('sync_retry'));
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.pump();
    verify(() => cubit.retry()).called(1);
  });

  testWidgets('non-retryable error → no retry button', (tester) async {
    whenListen(
      cubit,
      const Stream<HierarchySyncState>.empty(),
      initialState: const HierarchySyncState(
        stage: SyncStage.error,
        errorCode: 'validation_failed',
        errorMessage: 'bad cursor',
        retryable: false,
      ),
    );

    await pumpRouted(tester);

    expect(find.text('bad cursor'), findsOneWidget);
    expect(find.byKey(const Key('sync_retry')), findsNothing);
  });

  testWidgets('complete → navigates to /companies', (tester) async {
    whenListen(
      cubit,
      Stream.fromIterable(const [
        HierarchySyncState(stage: SyncStage.syncing),
        HierarchySyncState(stage: SyncStage.complete),
      ]),
      initialState: const HierarchySyncState(stage: SyncStage.syncing),
    );

    await pumpRouted(tester);
    await tester.pumpAndSettle();

    expect(find.text('COMPANIES'), findsOneWidget);
  });
}
