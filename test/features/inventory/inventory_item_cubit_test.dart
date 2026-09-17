import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/inventory/data/inventory_api.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_item_detail.dart';
import 'package:iams_mobile/features/inventory/data/models/outbox_entry.dart';
import 'package:iams_mobile/features/inventory/data/outbox_repository.dart';
import 'package:iams_mobile/features/inventory/presentation/detail/inventory_item_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/inventory_fixtures.dart';

class MockInventoryApi extends Mock implements InventoryApi {}

class MockOutboxRepository extends Mock implements OutboxRepository {}

InventoryItemDetail _detail({double binQty = 10, int version = 3}) =>
    InventoryItemDetail(
      id: 'item-1',
      sku: 'S1',
      name: 'Widget',
      isActive: true,
      totalQuantityOnHand: binQty,
      stockByBin: [
        StockByBin(binId: 'bin-1', quantityOnHand: binQty, version: version),
      ],
      movements: const [],
    );

OutboxEntry _pendingReceive(double qty) => OutboxEntry(
      idempotencyKey: 'k1',
      kind: MutationKind.receive,
      inventoryItemId: 'item-1',
      payload: {'destinationBinId': 'bin-1', 'quantity': qty},
      status: OutboxStatus.pending,
      createdAtUtc: DateTime.utc(2026, 1, 1),
    );

void main() {
  setUpAll(() => registerFallbackValue(_detail()));

  late MockInventoryApi api;
  late MockOutboxRepository outbox;

  setUp(() {
    api = MockInventoryApi();
    outbox = MockOutboxRepository();
    when(() => outbox.reconcileFromDetail(any())).thenAnswer((_) async {});
  });

  InventoryItemCubit build() =>
      InventoryItemCubit(api, outbox, itemId: 'item-1');

  test('loaded overlays a pending receive delta on the observed on-hand',
      () async {
    when(() => api.getItem('item-1')).thenAnswer((_) async => _detail());
    when(() => outbox.outboxForItem('item-1'))
        .thenAnswer((_) async => [_pendingReceive(5)]);

    final cubit = build();
    await cubit.load();

    expect(cubit.state.status, ItemDetailStatus.loaded);
    final bin = cubit.state.bins.single;
    expect(bin.observedQty, 10);
    expect(bin.pendingDelta, 5);
    expect(bin.effectiveQty, 15);
    expect(bin.hasPending, isTrue);
    expect(cubit.state.pending, hasLength(1));
  });

  test('404 maps to notFound (no existence leak), not error', () async {
    when(() => api.getItem('item-1')).thenThrow(const ApiException(
        code: ApiErrorCode.notFound, message: 'nope', statusCode: 404));

    final cubit = build();
    await cubit.load();

    expect(cubit.state.status, ItemDetailStatus.notFound);
  });

  test('network failure falls back to the offline cache + pending', () async {
    when(() => api.getItem('item-1')).thenThrow(
        const ApiException(code: ApiErrorCode.network, message: 'offline'));
    when(() => outbox.cachedLevelsForItem('item-1'))
        .thenAnswer((_) async => [cachedLevel('item-1', 'bin-1', qty: 8, version: 2)]);
    when(() => outbox.outboxForItem('item-1'))
        .thenAnswer((_) async => [_pendingReceive(3)]);

    final cubit = build();
    await cubit.load();

    expect(cubit.state.status, ItemDetailStatus.offline);
    expect(cubit.state.isOffline, isTrue);
    final bin = cubit.state.bins.single;
    expect(bin.observedQty, 8);
    expect(bin.effectiveQty, 11); // 8 + pending 3
  });
}
