import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/outbox_entry.dart';
import 'package:iams_mobile/features/inventory/data/outbox_repository.dart';
import 'package:iams_mobile/features/inventory/presentation/adjust/adjustment_cubit.dart';
import 'package:iams_mobile/features/inventory/presentation/count/stock_count_cubit.dart';
import 'package:iams_mobile/features/inventory/presentation/receive/receive_cubit.dart';
import 'package:iams_mobile/features/inventory/presentation/shared/mutation_state.dart';
import 'package:iams_mobile/features/inventory/presentation/transfer/transfer_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockOutboxRepository extends Mock implements OutboxRepository {}

OutboxEntry _entry(MutationKind kind) => OutboxEntry(
      idempotencyKey: 'k',
      kind: kind,
      inventoryItemId: 'i',
      payload: const {},
      status: OutboxStatus.synced,
      createdAtUtc: DateTime.utc(2026, 1, 1),
    );

MutationResult _applied(MutationKind kind) => MutationResult(
      outcome: MutationOutcome.applied,
      entry: _entry(kind),
    );

void main() {
  late MockOutboxRepository outbox;

  setUp(() => outbox = MockOutboxRepository());

  group('ReceiveCubit', () {
    test('blocks submit with no bin / non-positive qty (repo untouched)',
        () async {
      final cubit = ReceiveCubit(outbox);
      await cubit.submit(
          inventoryItemId: 'i', destinationBinId: null, quantity: 10);
      expect(cubit.state.validationMessage, isNotNull);
      expect(cubit.state.phase, MutationPhase.editing);

      await cubit.submit(
          inventoryItemId: 'i', destinationBinId: 'b', quantity: 0);
      expect(cubit.state.validationMessage, isNotNull);

      verifyNever(() => outbox.receive(
          inventoryItemId: any(named: 'inventoryItemId'),
          destinationBinId: any(named: 'destinationBinId'),
          quantity: any(named: 'quantity')));
    });

    test('valid submit calls the repo and reports the outcome', () async {
      when(() => outbox.receive(
              inventoryItemId: any(named: 'inventoryItemId'),
              destinationBinId: any(named: 'destinationBinId'),
              quantity: any(named: 'quantity')))
          .thenAnswer((_) async => _applied(MutationKind.receive));
      final cubit = ReceiveCubit(outbox);

      await cubit.submit(
          inventoryItemId: 'i', destinationBinId: 'b', quantity: 10);

      expect(cubit.state.phase, MutationPhase.done);
      expect(cubit.state.outcome, MutationOutcome.applied);
    });
  });

  group('TransferCubit', () {
    test('rejects same source/destination and over-source qty', () async {
      final cubit = TransferCubit(outbox);

      await cubit.submit(
          inventoryItemId: 'i',
          sourceBinId: 'b',
          destinationBinId: 'b',
          quantity: 1,
          sourceOnHand: 10);
      expect(cubit.state.validationMessage, contains('different'));

      await cubit.submit(
          inventoryItemId: 'i',
          sourceBinId: 'b1',
          destinationBinId: 'b2',
          quantity: 20,
          sourceOnHand: 10);
      expect(cubit.state.validationMessage, contains('available'));

      verifyNever(() => outbox.transfer(
          inventoryItemId: any(named: 'inventoryItemId'),
          sourceBinId: any(named: 'sourceBinId'),
          destinationBinId: any(named: 'destinationBinId'),
          quantity: any(named: 'quantity')));
    });
  });

  group('AdjustmentCubit', () {
    test('requires a reason and non-zero delta, and guards below-zero', () async {
      final cubit = AdjustmentCubit(outbox);

      await cubit.submit(
          inventoryItemId: 'i',
          binId: 'b',
          quantityDelta: 0,
          reason: 'x',
          binOnHand: 5);
      expect(cubit.state.validationMessage, contains('non-zero'));

      await cubit.submit(
          inventoryItemId: 'i',
          binId: 'b',
          quantityDelta: -3,
          reason: '',
          binOnHand: 5);
      expect(cubit.state.validationMessage, contains('reason'));

      await cubit.submit(
          inventoryItemId: 'i',
          binId: 'b',
          quantityDelta: -10,
          reason: 'damage',
          binOnHand: 5);
      expect(cubit.state.validationMessage, contains('below zero'));
    });
  });

  group('StockCountCubit', () {
    test('valid count submits and does not compute variance itself', () async {
      when(() => outbox.count(
              inventoryItemId: any(named: 'inventoryItemId'),
              binId: any(named: 'binId'),
              countedQuantity: any(named: 'countedQuantity')))
          .thenAnswer((_) async => _applied(MutationKind.count));
      final cubit = StockCountCubit(outbox);

      await cubit.submit(
          inventoryItemId: 'i', binId: 'b', countedQuantity: 12);

      expect(cubit.state.phase, MutationPhase.done);
      verify(() => outbox.count(
          inventoryItemId: 'i',
          binId: 'b',
          countedQuantity: 12)).called(1);
    });

    test('negative count is rejected client-side', () async {
      final cubit = StockCountCubit(outbox);
      await cubit.submit(
          inventoryItemId: 'i', binId: 'b', countedQuantity: -1);
      expect(cubit.state.validationMessage, isNotNull);
    });
  });
}
