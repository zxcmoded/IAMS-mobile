import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/inventory/data/inventory_repository.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_item_detail.dart';
import 'package:iams_mobile/features/inventory/data/models/outbox_entry.dart';
import 'package:iams_mobile/features/inventory/data/outbox_repository.dart';
import 'package:iams_mobile/features/inventory/presentation/detail/inventory_item_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockInventoryRepository extends Mock implements InventoryRepository {}

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
  late MockInventoryRepository repo;
  late MockOutboxRepository outbox;

  setUp(() {
    repo = MockInventoryRepository();
    outbox = MockOutboxRepository();
  });

  InventoryItemCubit build() =>
      InventoryItemCubit(repo, outbox, itemId: 'item-1');

  test('loaded reads from local cache and overlays a pending receive delta',
      () async {
    when(() => repo.getItemDetail('item-1')).thenAnswer((_) async => _detail());
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
    // Read path is local-only: the detail comes from the repository (SQLite),
    // consulted exactly once — there is no online item fetch.
    verify(() => repo.getItemDetail('item-1')).called(1);
  });

  test('an item absent from the local cache maps to notFound', () async {
    when(() => repo.getItemDetail('item-1')).thenAnswer((_) async => null);
    when(() => outbox.outboxForItem('item-1')).thenAnswer((_) async => const []);

    final cubit = build();
    await cubit.load();

    expect(cubit.state.status, ItemDetailStatus.notFound);
  });

  test('pending rows still surface even when the item is not cached', () async {
    when(() => repo.getItemDetail('item-1')).thenAnswer((_) async => null);
    when(() => outbox.outboxForItem('item-1'))
        .thenAnswer((_) async => [_pendingReceive(3)]);

    final cubit = build();
    await cubit.load();

    expect(cubit.state.status, ItemDetailStatus.notFound);
    expect(cubit.state.pending, hasLength(1));
  });

  test('a local read failure surfaces the error state', () async {
    when(() => repo.getItemDetail('item-1')).thenThrow(Exception('sqlite boom'));
    when(() => outbox.outboxForItem('item-1')).thenAnswer((_) async => const []);

    final cubit = build();
    await cubit.load();

    expect(cubit.state.status, ItemDetailStatus.error);
  });
}
