import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/inventory/data/inventory_api.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/stock_count_response.dart';
import 'package:iams_mobile/features/inventory/data/models/stock_movement_response.dart';
import 'package:iams_mobile/features/inventory/data/outbox_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/inventory_fixtures.dart';

class MockInventoryApi extends Mock implements InventoryApi {}

const _network = ApiException(code: ApiErrorCode.network, message: 'offline');

StockMovementResponse _movement(
  List<(String, double, int)> levels, {
  bool replayed = false,
  TransactionType type = TransactionType.receive,
}) =>
    StockMovementResponse(
      transactionId: 'txn-1',
      transactionType: type,
      status: MovementStatus.applied,
      quantity: 1,
      replayed: replayed,
      stockLevels: levels
          .map((l) => StockLevelState(
              binId: l.$1, quantityOnHand: l.$2, version: l.$3))
          .toList(),
    );

StockCountResponse _count({
  required StockCountStatus status,
  double counted = 12,
  double system = 10,
  double variance = 2,
  int version = 4,
  bool replayed = false,
}) =>
    StockCountResponse(
      id: 'count-1',
      status: status,
      countedQuantity: counted,
      systemQuantity: system,
      variance: variance,
      varianceThreshold: 5,
      varianceThresholdType: VarianceThresholdType.absoluteQuantity,
      stockVersion: version,
      replayed: replayed,
    );

void main() {
  late MockInventoryApi api;
  late FakeOutboxLocalDataSource local;
  late OutboxRepository repo;

  setUp(() {
    api = MockInventoryApi();
    local = FakeOutboxLocalDataSource();
    repo = OutboxRepository(local, api, FakeDeviceIdProvider());
  });

  // Common stubs (individual tests override as needed).
  void stubReceiveOk() {
    when(() => api.receive(
          idempotencyKey: any(named: 'idempotencyKey'),
          inventoryItemId: any(named: 'inventoryItemId'),
          destinationBinId: any(named: 'destinationBinId'),
          quantity: any(named: 'quantity'),
          baseDestinationStockVersion:
              any(named: 'baseDestinationStockVersion'),
          deviceId: any(named: 'deviceId'),
          clientCreatedAtUtc: any(named: 'clientCreatedAtUtc'),
        )).thenAnswer((_) async => _movement([('bin-d', 15, 6)]));
  }

  List<int?> capturedReceiveBaseVersions() => verify(() => api.receive(
        idempotencyKey: any(named: 'idempotencyKey'),
        inventoryItemId: any(named: 'inventoryItemId'),
        destinationBinId: any(named: 'destinationBinId'),
        quantity: any(named: 'quantity'),
        baseDestinationStockVersion:
            captureAny(named: 'baseDestinationStockVersion'),
        deviceId: any(named: 'deviceId'),
        clientCreatedAtUtc: any(named: 'clientCreatedAtUtc'),
      )).captured.cast<int?>();

  group('receive — online happy path', () {
    test('applies, reconciles cache with server version, marks synced',
        () async {
      local.seedStock(cachedLevel('item-1', 'bin-d', qty: 5, version: 5));
      stubReceiveOk();

      final result = await repo.receive(
        inventoryItemId: 'item-1',
        destinationBinId: 'bin-d',
        quantity: 10,
      );

      expect(result.outcome, MutationOutcome.applied);
      expect(result.entry.status, OutboxStatus.synced);
      // Cache reconciled to the authoritative response, not the local guess.
      final cached = await local.getStockLevel('item-1', 'bin-d');
      expect(cached!.quantityOnHand, 15);
      expect(cached.version, 6);
    });

    test('first online attempt OMITS the base version (last-writer-wins)',
        () async {
      local.seedStock(cachedLevel('item-1', 'bin-d', qty: 5, version: 5));
      stubReceiveOk();

      await repo.receive(
          inventoryItemId: 'item-1', destinationBinId: 'bin-d', quantity: 10);

      // Even though we observed version 5, the first attempt sends null.
      expect(capturedReceiveBaseVersions(), [null]);
    });

    test('replayed:true response is treated as success, not double-applied',
        () async {
      when(() => api.receive(
            idempotencyKey: any(named: 'idempotencyKey'),
            inventoryItemId: any(named: 'inventoryItemId'),
            destinationBinId: any(named: 'destinationBinId'),
            quantity: any(named: 'quantity'),
            baseDestinationStockVersion:
                any(named: 'baseDestinationStockVersion'),
            deviceId: any(named: 'deviceId'),
            clientCreatedAtUtc: any(named: 'clientCreatedAtUtc'),
          )).thenAnswer(
          (_) async => _movement([('bin-d', 15, 6)], replayed: true));

      final result = await repo.receive(
          inventoryItemId: 'item-1', destinationBinId: 'bin-d', quantity: 10);

      expect(result.outcome, MutationOutcome.replayed);
      expect(result.entry.status, OutboxStatus.synced);
    });
  });

  group('receive — offline then replay', () {
    test('network failure queues the row (pending, attempt 1)', () async {
      when(() => api.receive(
            idempotencyKey: any(named: 'idempotencyKey'),
            inventoryItemId: any(named: 'inventoryItemId'),
            destinationBinId: any(named: 'destinationBinId'),
            quantity: any(named: 'quantity'),
            baseDestinationStockVersion:
                any(named: 'baseDestinationStockVersion'),
            deviceId: any(named: 'deviceId'),
            clientCreatedAtUtc: any(named: 'clientCreatedAtUtc'),
          )).thenThrow(_network);

      final result = await repo.receive(
          inventoryItemId: 'item-1', destinationBinId: 'bin-d', quantity: 10);

      expect(result.outcome, MutationOutcome.queued);
      expect(result.entry.status, OutboxStatus.pending);
      expect(result.entry.attemptCount, 1);
      expect(await local.countByStatus([OutboxStatus.pending]), 1);
    });

    test('replay INCLUDES the stamped base version so conflicts can surface',
        () async {
      local.seedStock(cachedLevel('item-1', 'bin-d', qty: 5, version: 5));
      var calls = 0;
      when(() => api.receive(
            idempotencyKey: any(named: 'idempotencyKey'),
            inventoryItemId: any(named: 'inventoryItemId'),
            destinationBinId: any(named: 'destinationBinId'),
            quantity: any(named: 'quantity'),
            baseDestinationStockVersion:
                any(named: 'baseDestinationStockVersion'),
            deviceId: any(named: 'deviceId'),
            clientCreatedAtUtc: any(named: 'clientCreatedAtUtc'),
          )).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw _network;
        return _movement([('bin-d', 15, 6)]);
      });

      await repo.receive(
          inventoryItemId: 'item-1', destinationBinId: 'bin-d', quantity: 10);
      final summary = await repo.pushPending();

      expect(summary.accepted, 1);
      // First attempt null (online), replay carries the observed version 5.
      expect(capturedReceiveBaseVersions(), [null, 5]);
    });
  });

  group('receive — conflict & insufficient', () {
    test('409 marks conflict and rebases cache from conflicts[]', () async {
      local.seedStock(cachedLevel('item-1', 'bin-d', qty: 5, version: 1));
      when(() => api.receive(
            idempotencyKey: any(named: 'idempotencyKey'),
            inventoryItemId: any(named: 'inventoryItemId'),
            destinationBinId: any(named: 'destinationBinId'),
            quantity: any(named: 'quantity'),
            baseDestinationStockVersion:
                any(named: 'baseDestinationStockVersion'),
            deviceId: any(named: 'deviceId'),
            clientCreatedAtUtc: any(named: 'clientCreatedAtUtc'),
          )).thenThrow(const ApiException(
        code: ApiErrorCode.stockVersionConflict,
        message: 'conflict',
        statusCode: 409,
        extensions: {
          'conflicts': [
            {
              'binId': 'bin-d',
              'expectedVersion': 1,
              'currentVersion': 3,
              'currentQuantityOnHand': 99.0,
            }
          ],
        },
      ));

      final result = await repo.receive(
          inventoryItemId: 'item-1', destinationBinId: 'bin-d', quantity: 10);

      expect(result.outcome, MutationOutcome.conflict);
      expect(result.entry.status, OutboxStatus.conflict);
      expect(result.conflicts.single.currentVersion, 3);
      // Cache rebased to the server's current state for the next retry.
      final cached = await local.getStockLevel('item-1', 'bin-d');
      expect(cached!.version, 3);
      expect(cached.quantityOnHand, 99);
    });

    test('422 insufficient_stock marks the row failed', () async {
      when(() => api.receive(
            idempotencyKey: any(named: 'idempotencyKey'),
            inventoryItemId: any(named: 'inventoryItemId'),
            destinationBinId: any(named: 'destinationBinId'),
            quantity: any(named: 'quantity'),
            baseDestinationStockVersion:
                any(named: 'baseDestinationStockVersion'),
            deviceId: any(named: 'deviceId'),
            clientCreatedAtUtc: any(named: 'clientCreatedAtUtc'),
          )).thenThrow(const ApiException(
        code: ApiErrorCode.insufficientStock,
        message: 'not enough',
        statusCode: 422,
      ));

      final result = await repo.receive(
          inventoryItemId: 'item-1', destinationBinId: 'bin-d', quantity: 10);

      expect(result.outcome, MutationOutcome.insufficientStock);
      expect(result.entry.status, OutboxStatus.failed);
    });
  });

  group('count reconcile', () {
    void stubCount(StockCountResponse resp) {
      when(() => api.count(
            idempotencyKey: any(named: 'idempotencyKey'),
            inventoryItemId: any(named: 'inventoryItemId'),
            binId: any(named: 'binId'),
            countedQuantity: any(named: 'countedQuantity'),
            baseStockVersion: any(named: 'baseStockVersion'),
            deviceId: any(named: 'deviceId'),
            clientCreatedAtUtc: any(named: 'clientCreatedAtUtc'),
          )).thenAnswer((_) async => resp);
    }

    test('within-threshold count sets cached qty to counted quantity',
        () async {
      stubCount(_count(status: StockCountStatus.completed, counted: 12));
      final result = await repo.count(
          inventoryItemId: 'item-1', binId: 'bin-1', countedQuantity: 12);

      expect(result.outcome, MutationOutcome.applied);
      final cached = await local.getStockLevel('item-1', 'bin-1');
      expect(cached!.quantityOnHand, 12);
      expect(cached.version, 4);
    });

    test('over-threshold count keeps system qty (no stock change yet)',
        () async {
      stubCount(_count(
          status: StockCountStatus.pendingApproval, counted: 50, system: 10));
      final result = await repo.count(
          inventoryItemId: 'item-1', binId: 'bin-1', countedQuantity: 50);

      expect(result.outcome, MutationOutcome.applied);
      expect(result.count!.status.isPendingApproval, isTrue);
      // PendingApproval → no stock change: cache reflects the system snapshot.
      final cached = await local.getStockLevel('item-1', 'bin-1');
      expect(cached!.quantityOnHand, 10);
    });
  });

  group('pushPending ordering', () {
    test('stops on the first network failure, leaving the rest pending',
        () async {
      // Two receives queued offline.
      when(() => api.receive(
            idempotencyKey: any(named: 'idempotencyKey'),
            inventoryItemId: any(named: 'inventoryItemId'),
            destinationBinId: any(named: 'destinationBinId'),
            quantity: any(named: 'quantity'),
            baseDestinationStockVersion:
                any(named: 'baseDestinationStockVersion'),
            deviceId: any(named: 'deviceId'),
            clientCreatedAtUtc: any(named: 'clientCreatedAtUtc'),
          )).thenThrow(_network);
      await repo.receive(
          inventoryItemId: 'item-1', destinationBinId: 'bin-a', quantity: 1);
      await repo.receive(
          inventoryItemId: 'item-1', destinationBinId: 'bin-b', quantity: 2);

      // Reconnect: first succeeds, second network-fails.
      var calls = 0;
      when(() => api.receive(
            idempotencyKey: any(named: 'idempotencyKey'),
            inventoryItemId: any(named: 'inventoryItemId'),
            destinationBinId: any(named: 'destinationBinId'),
            quantity: any(named: 'quantity'),
            baseDestinationStockVersion:
                any(named: 'baseDestinationStockVersion'),
            deviceId: any(named: 'deviceId'),
            clientCreatedAtUtc: any(named: 'clientCreatedAtUtc'),
          )).thenAnswer((_) async {
        calls++;
        if (calls == 1) return _movement([('bin-a', 1, 1)]);
        throw _network;
      });

      final summary = await repo.pushPending();

      expect(summary.accepted, 1);
      expect(summary.stoppedOffline, isTrue);
      expect(await local.countByStatus([OutboxStatus.pending]), 1);
    });
  });

  group('discard', () {
    test('removes the queued row entirely', () async {
      when(() => api.receive(
            idempotencyKey: any(named: 'idempotencyKey'),
            inventoryItemId: any(named: 'inventoryItemId'),
            destinationBinId: any(named: 'destinationBinId'),
            quantity: any(named: 'quantity'),
            baseDestinationStockVersion:
                any(named: 'baseDestinationStockVersion'),
            deviceId: any(named: 'deviceId'),
            clientCreatedAtUtc: any(named: 'clientCreatedAtUtc'),
          )).thenThrow(_network);
      final result = await repo.receive(
          inventoryItemId: 'item-1', destinationBinId: 'bin-d', quantity: 10);

      await repo.discardEntry(result.entry.idempotencyKey);

      expect(await local.getOutbox(result.entry.idempotencyKey), isNull);
    });
  });
}
