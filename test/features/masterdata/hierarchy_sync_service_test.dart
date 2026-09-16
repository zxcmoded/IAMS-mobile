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
import 'package:mocktail/mocktail.dart';

import '../../support/masterdata_fixtures.dart';

class MockHierarchyApi extends Mock implements HierarchyApi {}

const _network = ApiException(code: ApiErrorCode.network, message: 'offline');

void main() {
  late MockHierarchyApi api;
  late FakeHierarchyLocalDataSource local;
  late HierarchySyncService service;

  setUp(() {
    api = MockHierarchyApi();
    local = FakeHierarchyLocalDataSource();
    service = HierarchySyncService(local, api);

    // Sensible defaults — a single final page per level. Individual tests
    // override the levels they exercise.
    when(() => api.getCompanies(
            cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => page<Company>([company('co1')],
            nextCursor: 'cc', hasMore: false));
    when(() => api.getLocations(
            parentId: any(named: 'parentId'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async =>
            page<Location>([location('l1')], nextCursor: 'lc', hasMore: false));
    when(() => api.getWarehouses(
            parentId: any(named: 'parentId'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => page<Warehouse>([warehouse('w1')],
            nextCursor: 'wc', hasMore: false));
    when(() => api.getRacks(
            parentId: any(named: 'parentId'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer(
            (_) async => page<Rack>([rack('r1')], nextCursor: 'rc', hasMore: false));
    when(() => api.getBins(
            parentId: any(named: 'parentId'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer(
            (_) async => page<Bin>([bin('b1')], nextCursor: 'bc', hasMore: false));
  });

  group('checkIsFullySynced', () {
    test('false when no metadata exists', () async {
      expect(await service.checkIsFullySynced(), isFalse);
    });

    test('true only when all five levels are complete', () async {
      for (final level in SyncLevels.all) {
        local.seedMetadata(
            SyncMetadata(entity: level, syncStatus: SyncStatus.complete));
      }
      expect(await service.checkIsFullySynced(), isTrue);

      local.seedMetadata(const SyncMetadata(
          entity: SyncLevels.bin, syncStatus: SyncStatus.inProgress));
      expect(await service.checkIsFullySynced(), isFalse);
    });
  });

  group('(a) full initial sync happy path', () {
    test('all levels complete, fetched in dependency order', () async {
      final order = <String>[];
      void record(String level) => order.add(level);
      when(() => api.getCompanies(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        record('company');
        return page<Company>([company('co1')], nextCursor: 'cc');
      });
      when(() => api.getLocations(
              parentId: any(named: 'parentId'),
              cursor: any(named: 'cursor'),
              pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        record('location');
        return page<Location>([location('l1')], nextCursor: 'lc');
      });
      when(() => api.getWarehouses(
              parentId: any(named: 'parentId'),
              cursor: any(named: 'cursor'),
              pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        record('warehouse');
        return page<Warehouse>([warehouse('w1')], nextCursor: 'wc');
      });
      when(() => api.getRacks(
              parentId: any(named: 'parentId'),
              cursor: any(named: 'cursor'),
              pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        record('rack');
        return page<Rack>([rack('r1')], nextCursor: 'rc');
      });
      when(() => api.getBins(
              parentId: any(named: 'parentId'),
              cursor: any(named: 'cursor'),
              pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        record('bin');
        return page<Bin>([bin('b1')], nextCursor: 'bc');
      });

      await service.run();

      expect(order, ['company', 'location', 'warehouse', 'rack', 'bin']);
      expect(await service.checkIsFullySynced(), isTrue);
      // Rows landed in the local store.
      expect(local.rowCount('company'), 1);
      expect(local.rowCount('bin'), 1);
      // Snapshot captured the reachable company set.
      expect(await local.readReachableSnapshot(), {'co1'});
    });

    test('reports progress per level', () async {
      final levels = <String>{};
      await service.run(onProgress: (p) => levels.add(p.level));
      expect(levels, containsAll(SyncLevels.all));
    });
  });

  group('(b) failure on Rack page 2', () {
    setUp(() {
      var rackCall = 0;
      when(() => api.getRacks(
              parentId: any(named: 'parentId'),
              cursor: any(named: 'cursor'),
              pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        rackCall++;
        if (rackCall == 1) {
          return page<Rack>([rack('r1')], nextCursor: 'r1', hasMore: true);
        }
        throw _network;
      });
    });

    test('upstream complete, rack inProgress at committed cursor, bin untouched',
        () async {
      await expectLater(service.run(), throwsA(isA<ApiException>()));

      expect(local.metaOf('company')!.syncStatus, SyncStatus.complete);
      expect(local.metaOf('location')!.syncStatus, SyncStatus.complete);
      expect(local.metaOf('warehouse')!.syncStatus, SyncStatus.complete);

      final rackMeta = local.metaOf('rack')!;
      expect(rackMeta.syncStatus, SyncStatus.inProgress);
      expect(rackMeta.lastCursor, 'r1'); // page 1's cursor durably committed

      // Bin's sync loop never ran: no rows, and its status was never advanced
      // past the initial pending (the failure short-circuited before it).
      expect(local.metaOf('bin')!.syncStatus, SyncStatus.pending);
      expect(local.rowCount('bin'), 0);
    });

    test('surfaces the error via onProgress error channel', () async {
      SyncProgress? errored;
      await expectLater(
        service.run(onProgress: (p) {
          if (p.isError) errored = p;
        }),
        throwsA(isA<ApiException>()),
      );
      expect(errored, isNotNull);
      expect(errored!.level, 'rack');
      expect(errored!.errorCode, ApiErrorCode.network);
    });
  });

  group('(c) resume after partial failure', () {
    test('re-running resumes Rack from its cursor without re-fetching page 1',
        () async {
      final rackCursors = <String?>[];
      var rackCall = 0;
      when(() => api.getRacks(
              parentId: any(named: 'parentId'),
              cursor: any(named: 'cursor'),
              pageSize: any(named: 'pageSize')))
          .thenAnswer((invocation) async {
        rackCursors.add(invocation.namedArguments[#cursor] as String?);
        rackCall++;
        if (rackCall == 1) {
          return page<Rack>([rack('r1')], nextCursor: 'r1', hasMore: true);
        }
        if (rackCall == 2) {
          throw _network; // fails page 2 on the first run
        }
        return page<Rack>([rack('r2')], nextCursor: 'r2', hasMore: false);
      });

      // First run fails on rack page 2.
      await expectLater(service.run(), throwsA(isA<ApiException>()));

      // Second run resumes.
      await service.run();

      expect(await service.checkIsFullySynced(), isTrue);
      // Only the very first fetch ever used a null cursor (page 1). The resume
      // fetch used the persisted 'r1' cursor.
      expect(rackCursors, [null, 'r1', 'r1']);
      expect(rackCursors.where((c) => c == null), hasLength(1));
      // Both rack pages' rows are present.
      expect(local.rowCount('rack'), 2);
    });

    test('already-complete upstream levels are not re-fetched on resume',
        () async {
      var rackCall = 0;
      when(() => api.getRacks(
              parentId: any(named: 'parentId'),
              cursor: any(named: 'cursor'),
              pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        rackCall++;
        if (rackCall == 1) {
          return page<Rack>([rack('r1')], nextCursor: 'r1', hasMore: true);
        }
        if (rackCall == 2) throw _network;
        return page<Rack>([rack('r2')], hasMore: false);
      });

      await expectLater(service.run(), throwsA(isA<ApiException>()));
      clearInteractions(api);
      await service.run();

      // Company always re-runs (full), but location/warehouse were complete and
      // the reachable set didn't change, so they are skipped on resume.
      verifyNever(() => api.getLocations(
          parentId: any(named: 'parentId'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize')));
      verifyNever(() => api.getWarehouses(
          parentId: any(named: 'parentId'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize')));
    });
  });

  group('(d) reachable-set diff forces a downstream reset', () {
    test('a newly-reachable company re-pulls Location→Bin in full', () async {
      final locationCursors = <String?>[];
      when(() => api.getLocations(
              parentId: any(named: 'parentId'),
              cursor: any(named: 'cursor'),
              pageSize: any(named: 'pageSize')))
          .thenAnswer((invocation) async {
        locationCursors.add(invocation.namedArguments[#cursor] as String?);
        return page<Location>([location('l1')], nextCursor: 'lc');
      });

      var companies = [company('co1')];
      when(() => api.getCompanies(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => page<Company>(companies, nextCursor: 'cc'));

      // First full sync — snapshot becomes {co1}.
      await service.run();
      expect(await service.checkIsFullySynced(), isTrue);

      // A connection is enabled → co2 becomes reachable.
      companies = [company('co1'), company('co2')];
      await service.run();

      expect(await local.readReachableSnapshot(), {'co1', 'co2'});
      expect(await service.checkIsFullySynced(), isTrue);
      // Location was fully re-pulled (cursor null) on both passes — the reset
      // cleared its cursor rather than resuming.
      expect(locationCursors, [null, null]);
    });

    test('an unchanged reachable set does NOT reset downstream levels',
        () async {
      final locationCursors = <String?>[];
      when(() => api.getLocations(
              parentId: any(named: 'parentId'),
              cursor: any(named: 'cursor'),
              pageSize: any(named: 'pageSize')))
          .thenAnswer((invocation) async {
        locationCursors.add(invocation.namedArguments[#cursor] as String?);
        return page<Location>([location('l1')], nextCursor: 'lc');
      });

      await service.run();
      await service.run(); // same company set

      // Location fetched only on the first pass; the second skipped it.
      expect(locationCursors, [null]);
    });
  });

  group('run() always performs the cheap Company pass', () {
    test('an already fully-synced store still pulls Company (no-change pass)',
        () async {
      // Seed a fully-synced store whose reachable set matches what Company will
      // return, so nothing downstream should change.
      for (final level in SyncLevels.all) {
        local.seedMetadata(
            SyncMetadata(entity: level, syncStatus: SyncStatus.complete));
      }
      local.seedSnapshot({'co1'});
      expect(await service.checkIsFullySynced(), isTrue);

      var companyCalls = 0;
      when(() => api.getCompanies(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        companyCalls++;
        return page<Company>([company('co1')], nextCursor: 'cc');
      });

      await service.run();

      // Company is re-pulled every pass...
      expect(companyCalls, 1);
      // ...but with no reachable-set diff, children are skipped (still complete,
      // never re-fetched).
      verifyNever(() => api.getLocations(
          parentId: any(named: 'parentId'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize')));
      expect(await service.checkIsFullySynced(), isTrue);
    });
  });

  group('(e) empty page never clears the stored cursor', () {
    test('an empty Location page leaves last_cursor intact and completes',
        () async {
      // Location is mid-sync with a persisted cursor; everything else already
      // complete and the reachable set unchanged.
      local.seedSnapshot({'co1'});
      local.seedMetadata(const SyncMetadata(
        entity: SyncLevels.location,
        lastCursor: 'L5',
        syncStatus: SyncStatus.inProgress,
      ));
      for (final level in [
        SyncLevels.warehouse,
        SyncLevels.rack,
        SyncLevels.bin,
      ]) {
        local.seedMetadata(
            SyncMetadata(entity: level, syncStatus: SyncStatus.complete));
      }

      // The incremental poll returns an empty page: items [], nextCursor null.
      when(() => api.getLocations(
              parentId: any(named: 'parentId'),
              cursor: any(named: 'cursor'),
              pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async =>
              page<Location>([], nextCursor: null, hasMore: false));

      await service.run();

      final locationMeta = local.metaOf('location')!;
      expect(locationMeta.lastCursor, 'L5'); // NOT cleared
      expect(locationMeta.syncStatus, SyncStatus.complete);
    });
  });
}
