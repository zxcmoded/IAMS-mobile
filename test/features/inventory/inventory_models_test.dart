import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/util/uuid.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/outbox_entry.dart';

void main() {
  group('uuid', () {
    test('is a well-formed v4 UUID', () {
      final id = newUuidV4();
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
                r'[0-9a-f]{12}$')
            .hasMatch(id),
        isTrue,
        reason: id,
      );
    });

    test('is unique across calls', () {
      final ids = {for (var i = 0; i < 500; i++) newUuidV4()};
      expect(ids, hasLength(500));
    });
  });

  group('enum wire mapping', () {
    test('InventoryFilter wire tokens match the contract', () {
      expect(InventoryFilter.inStock.wire, 'in_stock');
      expect(InventoryFilter.lowStock.wire, 'low_stock');
      expect(InventoryFilter.outOfStock.wire, 'out_of_stock');
    });

    test('unknown wire values map to the forward-compat fallback', () {
      expect(TransactionType.fromWire('Nope'), TransactionType.unknown);
      expect(StockCountStatus.fromWire('Nope'), StockCountStatus.unknown);
    });
  });

  group('OutboxEntry', () {
    test('row round-trips payload + response JSON', () {
      final entry = OutboxEntry(
        idempotencyKey: 'k',
        kind: MutationKind.transfer,
        inventoryItemId: 'i',
        payload: const {
          'sourceBinId': 'b1',
          'destinationBinId': 'b2',
          'quantity': 4,
          'baseSourceStockVersion': 3,
        },
        status: OutboxStatus.pending,
        createdAtUtc: DateTime.utc(2026, 1, 1),
        attemptCount: 2,
        response: const {'transactionId': 't'},
      );

      final restored = OutboxEntry.fromRow(entry.toRow());

      expect(restored.kind, MutationKind.transfer);
      expect(restored.payload['quantity'], 4);
      expect(restored.payload['baseSourceStockVersion'], 3);
      expect(restored.attemptCount, 2);
      expect(restored.response!['transactionId'], 't');
      expect(restored.isReplay, isTrue);
    });

    test('pendingBinDeltas: transfer nets -qty source / +qty dest', () {
      final entry = OutboxEntry(
        idempotencyKey: 'k',
        kind: MutationKind.transfer,
        inventoryItemId: 'i',
        payload: const {
          'sourceBinId': 'b1',
          'destinationBinId': 'b2',
          'quantity': 4,
        },
        status: OutboxStatus.pending,
        createdAtUtc: DateTime.utc(2026, 1, 1),
      );

      expect(entry.pendingBinDeltas(), {'b1': -4.0, 'b2': 4.0});
    });

    test('pendingBinDeltas: count contributes no delta (absolute set)', () {
      final entry = OutboxEntry(
        idempotencyKey: 'k',
        kind: MutationKind.count,
        inventoryItemId: 'i',
        payload: const {'binId': 'b1', 'countedQuantity': 12},
        status: OutboxStatus.pending,
        createdAtUtc: DateTime.utc(2026, 1, 1),
      );

      expect(entry.pendingBinDeltas(), isEmpty);
    });
  });
}
