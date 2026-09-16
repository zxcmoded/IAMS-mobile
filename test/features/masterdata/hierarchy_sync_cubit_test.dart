import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_api.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_sync_service.dart';
import 'package:iams_mobile/features/masterdata/data/models/bin.dart';
import 'package:iams_mobile/features/masterdata/data/models/company.dart';
import 'package:iams_mobile/features/masterdata/data/models/location.dart';
import 'package:iams_mobile/features/masterdata/data/models/rack.dart';
import 'package:iams_mobile/features/masterdata/data/models/sync_metadata.dart';
import 'package:iams_mobile/features/masterdata/data/models/warehouse.dart';
import 'package:iams_mobile/features/masterdata/presentation/sync/hierarchy_sync_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/masterdata_fixtures.dart';

class MockHierarchyApi extends Mock implements HierarchyApi {}

/// These use the *real* cubit + real sync service over the in-memory local
/// fake, to prove the entry method never short-circuits past `run()` — the
/// reachability-gap mitigation depends on the Company pass firing every launch.
void main() {
  late MockHierarchyApi api;
  late FakeHierarchyLocalDataSource local;
  late HierarchySyncService service;

  void stubDefaults() {
    when(() => api.getCompanies(
            cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
        .thenAnswer(
            (_) async => page<Company>([company('co1')], nextCursor: 'cc'));
    when(() => api.getLocations(
            parentId: any(named: 'parentId'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer(
            (_) async => page<Location>([location('l1')], nextCursor: 'lc'));
    when(() => api.getWarehouses(
            parentId: any(named: 'parentId'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer(
            (_) async => page<Warehouse>([warehouse('w1')], nextCursor: 'wc'));
    when(() => api.getRacks(
            parentId: any(named: 'parentId'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => page<Rack>([rack('r1')], nextCursor: 'rc'));
    when(() => api.getBins(
            parentId: any(named: 'parentId'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => page<Bin>([bin('b1')], nextCursor: 'bc'));
  }

  setUp(() {
    api = MockHierarchyApi();
    local = FakeHierarchyLocalDataSource();
    service = HierarchySyncService(local, api);
    stubDefaults();
  });

  void seedFullySynced(Set<String> reachable) {
    for (final level in SyncLevels.all) {
      local.seedMetadata(
          SyncMetadata(entity: level, syncStatus: SyncStatus.complete));
    }
    local.seedSnapshot(reachable);
  }

  blocTest<HierarchySyncCubit, HierarchySyncState>(
    'already fully synced + no change → still pulls Company, ends complete',
    build: () => HierarchySyncCubit(service),
    setUp: () => seedFullySynced({'co1'}),
    act: (c) => c.checkAndSync(),
    expect: () => [
      isA<HierarchySyncState>()
          .having((s) => s.stage, 'stage', SyncStage.checking),
      isA<HierarchySyncState>()
          .having((s) => s.stage, 'stage', SyncStage.complete),
    ],
    verify: (_) {
      // The Company pass ran despite the store already being fully synced.
      verify(() => api.getCompanies(
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'))).called(1);
      // No visible child-level progress (quiet pass), so no re-fetch either.
      verifyNever(() => api.getLocations(
          parentId: any(named: 'parentId'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize')));
    },
  );

  blocTest<HierarchySyncCubit, HierarchySyncState>(
    'already fully synced + newly-reachable company → detects diff, re-pulls '
    'children, surfaces progress, ends complete',
    build: () => HierarchySyncCubit(service),
    setUp: () {
      seedFullySynced({'co1'});
      // A connection was enabled after the initial sync — co2 is now reachable.
      when(() => api.getCompanies(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => page<Company>(
              [company('co1'), company('co2')],
              nextCursor: 'cc'));
    },
    act: (c) => c.checkAndSync(),
    expect: () => [
      isA<HierarchySyncState>()
          .having((s) => s.stage, 'stage', SyncStage.checking),
      // Diff forced a real child-level re-pull → visible syncing progress.
      ...['location', 'warehouse', 'rack', 'bin'].map((lvl) =>
          isA<HierarchySyncState>()
              .having((s) => s.stage, 'stage', SyncStage.syncing)
              .having((s) => s.level, 'level', lvl)),
      isA<HierarchySyncState>()
          .having((s) => s.stage, 'stage', SyncStage.complete),
    ],
    verify: (_) {
      verify(() => api.getCompanies(
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'))).called(1);
      // Children were re-pulled in full (cursor null) because the diff reset
      // them — one call each here (single page).
      verify(() => api.getLocations(
          parentId: any(named: 'parentId'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'))).called(1);
      verify(() => api.getBins(
          parentId: any(named: 'parentId'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'))).called(1);
      expect(local.rowCount('company'), 2);
    },
  );

  blocTest<HierarchySyncCubit, HierarchySyncState>(
    'empty store → full visible sync, ends complete',
    build: () => HierarchySyncCubit(service),
    act: (c) => c.checkAndSync(),
    expect: () => [
      isA<HierarchySyncState>()
          .having((s) => s.stage, 'stage', SyncStage.syncing),
      // company + 4 children each emit at least once
      ...SyncLevels.all.map((lvl) => isA<HierarchySyncState>()
          .having((s) => s.stage, 'stage', SyncStage.syncing)
          .having((s) => s.level, 'level', lvl)),
      isA<HierarchySyncState>()
          .having((s) => s.stage, 'stage', SyncStage.complete),
    ],
  );

  blocTest<HierarchySyncCubit, HierarchySyncState>(
    'non-ApiException failure → error with a generic message, not stuck '
    'in syncing',
    build: () => HierarchySyncCubit(service),
    setUp: () {
      // A plain error (not an ApiException) from the Company pass — e.g. a
      // local DB write or a mapping TypeError — propagates through run() and
      // must land in the cubit's catch-all rather than hanging on syncing.
      when(() => api.getCompanies(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenThrow(StateError('local database unavailable'));
    },
    act: (c) => c.checkAndSync(),
    expect: () => [
      isA<HierarchySyncState>()
          .having((s) => s.stage, 'stage', SyncStage.syncing),
      isA<HierarchySyncState>()
          .having((s) => s.stage, 'stage', SyncStage.error)
          .having((s) => s.errorCode, 'code', ApiErrorCode.unknown)
          .having((s) => s.errorMessage, 'message', isNotNull)
          .having((s) => s.errorMessage, 'message',
              contains('Something went wrong'))
          .having((s) => s.retryable, 'retryable', isTrue),
    ],
  );
}
