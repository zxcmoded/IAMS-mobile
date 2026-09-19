import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/inventory/data/inventory_sync_api.dart';
import 'package:iams_mobile/features/inventory/data/inventory_sync_service.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_item_sync.dart';
import 'package:iams_mobile/features/inventory/data/models/stock_level_sync.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_api.dart';
import 'package:iams_mobile/features/masterdata/data/models/company.dart';
import 'package:iams_mobile/features/masterdata/data/models/sync_metadata.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/inventory_fixtures.dart';
import '../../support/masterdata_fixtures.dart';

class MockInventorySyncApi extends Mock implements InventorySyncApi {}

class MockHierarchyApi extends Mock implements HierarchyApi {}

const _network = ApiException(code: ApiErrorCode.network, message: 'offline');

void main() {
  late MockInventorySyncApi syncApi;
  late MockHierarchyApi companiesApi;
  late FakeInventoryLocalDataSource local;
  late InventorySyncService service;

  setUp(() {
    syncApi = MockInventorySyncApi();
    companiesApi = MockHierarchyApi();
    local = FakeInventoryLocalDataSource();
    service = InventorySyncService(local, syncApi, companiesApi);

    // Defaults — one final page per feed; a single reachable company.
    when(() => companiesApi.getCompanies(
            cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async =>
            page<Company>([company('co1')], nextCursor: 'cc', hasMore: false));
    when(() => syncApi.getItems(
            cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => page<InventoryItemSync>([itemSync('i1')],
            nextCursor: 'ic', hasMore: false));
    when(() => syncApi.getStockLevels(
            cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => page<StockLevelSync>(
            [stockLevelSync('s1', inventoryItemId: 'i1', binId: 'b1')],
            nextCursor: 'sc',
            hasMore: false));
  });

  group('checkIsFullySynced', () {
    test('false when no metadata exists', () async {
      expect(await service.checkIsFullySynced(), isFalse);
    });

    test('true only when both feeds are complete', () async {
      for (final e in InventorySyncEntities.all) {
        local.seedMetadata(
            SyncMetadata(entity: e, syncStatus: SyncStatus.complete));
      }
      expect(await service.checkIsFullySynced(), isTrue);

      local.seedMetadata(const SyncMetadata(
          entity: InventorySyncEntities.stockLevel,
          syncStatus: SyncStatus.inProgress));
      expect(await service.checkIsFullySynced(), isFalse);
    });
  });

  group('(a) full initial sync happy path', () {
    test('items then stock, in dependency order; both complete', () async {
      final order = <String>[];
      when(() => syncApi.getItems(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        order.add('inventory_item');
        return page<InventoryItemSync>([itemSync('i1')], nextCursor: 'ic');
      });
      when(() => syncApi.getStockLevels(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        order.add('stock_level');
        return page<StockLevelSync>(
            [stockLevelSync('s1', inventoryItemId: 'i1', binId: 'b1')],
            nextCursor: 'sc');
      });

      await service.run();

      expect(order, ['inventory_item', 'stock_level']);
      expect(await service.checkIsFullySynced(), isTrue);
      expect(local.itemCount(), 1);
      expect(local.stockCount(), 1);
      expect(await local.readReachableSnapshot(), {'co1'});
    });

    test('reports progress per feed', () async {
      final entities = <String>{};
      await service.run(onProgress: (p) => entities.add(p.entity));
      expect(entities, containsAll(InventorySyncEntities.all));
    });
  });

  group('(b) failure on stock-level page 2', () {
    setUp(() {
      var call = 0;
      when(() => syncApi.getStockLevels(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        call++;
        if (call == 1) {
          return page<StockLevelSync>(
              [stockLevelSync('s1', inventoryItemId: 'i1', binId: 'b1')],
              nextCursor: 's1',
              hasMore: true);
        }
        throw _network;
      });
    });

    test('item feed complete, stock inProgress at committed cursor', () async {
      await expectLater(service.run(), throwsA(isA<ApiException>()));

      expect(local.metaOf('inventory_item')!.syncStatus, SyncStatus.complete);
      final stockMeta = local.metaOf('stock_level')!;
      expect(stockMeta.syncStatus, SyncStatus.inProgress);
      expect(stockMeta.lastCursor, 's1'); // page 1's cursor durably committed
    });

    test('surfaces the error via onProgress error channel', () async {
      InventorySyncProgress? errored;
      await expectLater(
        service.run(onProgress: (p) {
          if (p.isError) errored = p;
        }),
        throwsA(isA<ApiException>()),
      );
      expect(errored, isNotNull);
      expect(errored!.entity, 'stock_level');
      expect(errored!.errorCode, ApiErrorCode.network);
    });
  });

  group('(c) resume after partial failure', () {
    test('re-running resumes stock from its cursor without re-fetching page 1',
        () async {
      final cursors = <String?>[];
      var call = 0;
      when(() => syncApi.getStockLevels(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((invocation) async {
        cursors.add(invocation.namedArguments[#cursor] as String?);
        call++;
        if (call == 1) {
          return page<StockLevelSync>(
              [stockLevelSync('s1', inventoryItemId: 'i1', binId: 'b1')],
              nextCursor: 's1',
              hasMore: true);
        }
        if (call == 2) throw _network;
        return page<StockLevelSync>(
            [stockLevelSync('s2', inventoryItemId: 'i1', binId: 'b2')],
            nextCursor: 's2',
            hasMore: false);
      });

      await expectLater(service.run(), throwsA(isA<ApiException>()));
      await service.run();

      expect(await service.checkIsFullySynced(), isTrue);
      expect(cursors, [null, 's1', 's1']);
      expect(cursors.where((c) => c == null), hasLength(1));
      expect(local.stockCount(), 2);
    });

    test('already-complete item feed is not re-fetched on resume', () async {
      var call = 0;
      when(() => syncApi.getStockLevels(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        call++;
        if (call == 1) {
          return page<StockLevelSync>(
              [stockLevelSync('s1', inventoryItemId: 'i1', binId: 'b1')],
              nextCursor: 's1',
              hasMore: true);
        }
        if (call == 2) throw _network;
        return page<StockLevelSync>(
            [stockLevelSync('s2', inventoryItemId: 'i1', binId: 'b2')],
            hasMore: false);
      });

      await expectLater(service.run(), throwsA(isA<ApiException>()));
      clearInteractions(syncApi);
      await service.run();

      // The item feed was complete and the reachable set didn't change → skipped.
      verifyNever(() => syncApi.getItems(
          cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')));
    });
  });

  group('(d) reachable-set diff forces a full re-pull of BOTH feeds', () {
    test('a newly-reachable company re-pulls items and stock with cursor null',
        () async {
      final itemCursors = <String?>[];
      when(() => syncApi.getItems(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((invocation) async {
        itemCursors.add(invocation.namedArguments[#cursor] as String?);
        return page<InventoryItemSync>([itemSync('i1')], nextCursor: 'ic');
      });

      var companies = [company('co1')];
      when(() => companiesApi.getCompanies(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => page<Company>(companies, nextCursor: 'cc'));

      await service.run(); // snapshot becomes {co1}
      expect(await service.checkIsFullySynced(), isTrue);

      companies = [company('co1'), company('co2')]; // connection enabled
      await service.run();

      expect(await local.readReachableSnapshot(), {'co1', 'co2'});
      expect(await service.checkIsFullySynced(), isTrue);
      // Both passes pulled items from cursor null — the reset cleared it.
      expect(itemCursors, [null, null]);
    });

    test('an unchanged reachable set does NOT reset the feeds', () async {
      final itemCursors = <String?>[];
      when(() => syncApi.getItems(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((invocation) async {
        itemCursors.add(invocation.namedArguments[#cursor] as String?);
        return page<InventoryItemSync>([itemSync('i1')], nextCursor: 'ic');
      });

      await service.run();
      await service.run(); // same company set

      // Items fetched only on the first pass; the second skipped the feed.
      expect(itemCursors, [null]);
    });
  });

  group('(e) empty page never clears the stored cursor', () {
    test('an empty item page leaves last_cursor intact and completes',
        () async {
      local.seedSnapshot({'co1'});
      local.seedMetadata(const SyncMetadata(
        entity: InventorySyncEntities.item,
        lastCursor: 'I5',
        syncStatus: SyncStatus.inProgress,
      ));
      local.seedMetadata(const SyncMetadata(
          entity: InventorySyncEntities.stockLevel,
          syncStatus: SyncStatus.complete));

      when(() => syncApi.getItems(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async =>
              page<InventoryItemSync>([], nextCursor: null, hasMore: false));

      await service.run();

      final itemMeta = local.metaOf('inventory_item')!;
      expect(itemMeta.lastCursor, 'I5'); // NOT cleared
      expect(itemMeta.syncStatus, SyncStatus.complete);
    });
  });

  group('run() always performs the cheap Company pass', () {
    test('an already fully-synced store still pulls Company (no-change pass)',
        () async {
      for (final e in InventorySyncEntities.all) {
        local.seedMetadata(
            SyncMetadata(entity: e, syncStatus: SyncStatus.complete));
      }
      local.seedSnapshot({'co1'});

      var companyCalls = 0;
      when(() => companiesApi.getCompanies(
              cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async {
        companyCalls++;
        return page<Company>([company('co1')], nextCursor: 'cc');
      });

      await service.run();

      expect(companyCalls, 1);
      verifyNever(() => syncApi.getItems(
          cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')));
      verifyNever(() => syncApi.getStockLevels(
          cursor: any(named: 'cursor'), pageSize: any(named: 'pageSize')));
    });
  });
}
