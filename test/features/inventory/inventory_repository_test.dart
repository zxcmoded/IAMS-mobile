import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/inventory/data/inventory_repository.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/outbox_entry.dart';

import '../../support/inventory_fixtures.dart';

/// The repository is constructed with **only** local data sources — no API
/// client — so a screen reading through it physically cannot reach the network.
/// These tests confirm the offline list/detail computation matches the server's
/// old `ListInventory` semantics (search / filter / aggregate on-hand / sku
/// sort / offset pagination) and that pending-outbox deltas overlay correctly.
void main() {
  late FakeInventoryLocalDataSource local;
  late FakeOutboxLocalDataSource outbox;
  late InventoryRepository repo;

  setUp(() {
    local = FakeInventoryLocalDataSource();
    outbox = FakeOutboxLocalDataSource();
    repo = InventoryRepository(local, outbox);
  });

  OutboxEntry receive(String item, String bin, double qty) => OutboxEntry(
        idempotencyKey: '$item-$bin-$qty',
        kind: MutationKind.receive,
        inventoryItemId: item,
        payload: {'destinationBinId': bin, 'quantity': qty},
        status: OutboxStatus.pending,
        createdAtUtc: DateTime.utc(2026, 1, 1),
      );

  group('aggregate on-hand', () {
    test('sums quantity across all of an item\'s bins (LEFT JOIN)', () async {
      local.seedItem(itemSync('i1', sku: 'A'));
      local.seedStock(stockLevelSync('s1',
          inventoryItemId: 'i1', binId: 'b1', quantityOnHand: 3));
      local.seedStock(stockLevelSync('s2',
          inventoryItemId: 'i1', binId: 'b2', quantityOnHand: 4));

      final page = await repo.getList();

      expect(page.items.single.totalQuantityOnHand, 7);
    });

    test('an item with no stock rows aggregates to 0 and still appears',
        () async {
      local.seedItem(itemSync('i1', sku: 'A'));

      final page = await repo.getList();

      expect(page.items.single.totalQuantityOnHand, 0);
    });
  });

  group('filter (over effective total)', () {
    setUp(() {
      local.seedItem(itemSync('zero', sku: 'A')); // total 0
      local.seedItem(itemSync('low', sku: 'B'));
      local.seedStock(stockLevelSync('s-low',
          inventoryItemId: 'low', binId: 'b1', quantityOnHand: 5)); // <= 10
      local.seedItem(itemSync('high', sku: 'C'));
      local.seedStock(stockLevelSync('s-high',
          inventoryItemId: 'high', binId: 'b1', quantityOnHand: 100));
    });

    test('all returns everything', () async {
      final page = await repo.getList(filter: InventoryFilter.all);
      expect(page.items.map((i) => i.id), ['zero', 'low', 'high']);
    });

    test('in_stock excludes zero on-hand', () async {
      final page = await repo.getList(filter: InventoryFilter.inStock);
      expect(page.items.map((i) => i.id), ['low', 'high']);
    });

    test('out_of_stock keeps only <= 0', () async {
      final page = await repo.getList(filter: InventoryFilter.outOfStock);
      expect(page.items.map((i) => i.id), ['zero']);
    });

    test('low_stock keeps 0 < total <= threshold (default 10)', () async {
      final page = await repo.getList(filter: InventoryFilter.lowStock);
      expect(page.items.map((i) => i.id), ['low']);
    });

    test('low_stock honours an explicit threshold', () async {
      final page = await repo.getList(
          filter: InventoryFilter.lowStock, lowStockThreshold: 200);
      // Now both the 5-on-hand and 100-on-hand items qualify.
      expect(page.items.map((i) => i.id), ['low', 'high']);
    });
  });

  group('search', () {
    setUp(() {
      local.seedItem(itemSync('i1', sku: 'WIDGET-1', name: 'Blue widget'));
      local.seedItem(
          itemSync('i2', sku: 'GADGET-9', name: 'Red gadget', barcode: '5551234'));
    });

    test('case-insensitive substring over sku', () async {
      final page = await repo.getList(search: 'widget');
      expect(page.items.map((i) => i.id), ['i1']);
    });

    test('matches name', () async {
      final page = await repo.getList(search: 'red');
      expect(page.items.map((i) => i.id), ['i2']);
    });

    test('matches barcode', () async {
      final page = await repo.getList(search: '5551');
      expect(page.items.map((i) => i.id), ['i2']);
    });
  });

  group('sort + pagination', () {
    setUp(() {
      // Insert out of order; expect sku-then-id ordering.
      for (final sku in ['C', 'A', 'B', 'a']) {
        local.seedItem(itemSync('id-$sku', sku: sku));
      }
    });

    test('sorted case-insensitively by sku', () async {
      final page = await repo.getList(pageSize: 10);
      // 'A' and 'a' tie on sku (case-insensitive) → id tiebreak: 'id-A' < 'id-a'.
      expect(page.items.map((i) => i.sku), ['A', 'a', 'B', 'C']);
    });

    test('offset pagination with peek-ahead hasMore', () async {
      final first = await repo.getList(page: 1, pageSize: 2);
      expect(first.items.map((i) => i.sku), ['A', 'a']);
      expect(first.hasMore, isTrue);

      final second = await repo.getList(page: 2, pageSize: 2);
      expect(second.items.map((i) => i.sku), ['B', 'C']);
      expect(second.hasMore, isFalse);
    });
  });

  group('pending overlay', () {
    test('a queued receive lifts the effective total (and its filter bucket)',
        () async {
      local.seedItem(itemSync('i1', sku: 'A')); // confirmed total 0
      await outbox.insertOutbox(receive('i1', 'b1', 6));

      final all = await repo.getList();
      expect(all.items.single.totalQuantityOnHand, 6);

      // With +6 pending it now qualifies as in_stock, not out_of_stock.
      final inStock = await repo.getList(filter: InventoryFilter.inStock);
      expect(inStock.items.map((i) => i.id), ['i1']);
      final out = await repo.getList(filter: InventoryFilter.outOfStock);
      expect(out.items, isEmpty);
    });

    test('a queued transfer nets to zero at the item level', () async {
      local.seedItem(itemSync('i1', sku: 'A'));
      local.seedStock(stockLevelSync('s1',
          inventoryItemId: 'i1', binId: 'b1', quantityOnHand: 10));
      await outbox.insertOutbox(OutboxEntry(
        idempotencyKey: 't1',
        kind: MutationKind.transfer,
        inventoryItemId: 'i1',
        payload: {'sourceBinId': 'b1', 'destinationBinId': 'b2', 'quantity': 4},
        status: OutboxStatus.pending,
        createdAtUtc: DateTime.utc(2026, 1, 1),
      ));

      final page = await repo.getList();
      expect(page.items.single.totalQuantityOnHand, 10); // unchanged
    });
  });

  group('getItemDetail', () {
    test('builds detail + per-bin breakdown from local tables', () async {
      local.seedItem(itemSync('i1', sku: 'A', name: 'Widget'));
      local.seedStock(stockLevelSync('s1',
          inventoryItemId: 'i1', binId: 'b2', quantityOnHand: 2, version: 7));
      local.seedStock(stockLevelSync('s2',
          inventoryItemId: 'i1', binId: 'b1', quantityOnHand: 3, version: 4));

      final detail = await repo.getItemDetail('i1');

      expect(detail, isNotNull);
      expect(detail!.name, 'Widget');
      expect(detail.totalQuantityOnHand, 5);
      expect(detail.stockByBin.map((b) => b.binId), ['b1', 'b2']); // sorted
      expect(detail.movements, isEmpty); // out of scope offline
    });

    test('returns null for an item not in the local cache', () async {
      expect(await repo.getItemDetail('nope'), isNull);
    });
  });
}
