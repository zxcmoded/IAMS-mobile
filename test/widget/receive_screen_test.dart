import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/outbox_entry.dart';
import 'package:iams_mobile/features/inventory/data/outbox_repository.dart';
import 'package:iams_mobile/features/inventory/presentation/receive/receive_cubit.dart';
import 'package:iams_mobile/features/inventory/presentation/receive/receive_screen.dart';
import 'package:iams_mobile/features/inventory/presentation/shared/mutation_args.dart';
import 'package:iams_mobile/features/inventory/presentation/shared/mutation_state.dart';
import 'package:mocktail/mocktail.dart';

class MockReceiveCubit extends MockCubit<MutationState>
    implements ReceiveCubit {}

const _args = MutationArgs(
  itemId: 'item-1',
  sku: 'S1',
  name: 'Widget',
  bins: [BinOption(binId: 'bin-1', onHand: 10, version: 3)],
);

MutationResult _queued() => MutationResult(
      outcome: MutationOutcome.queued,
      entry: OutboxEntry(
        idempotencyKey: 'k',
        kind: MutationKind.receive,
        inventoryItemId: 'item-1',
        payload: const {},
        status: OutboxStatus.pending,
        createdAtUtc: DateTime.utc(2026, 1, 1),
      ),
    );

void main() {
  late MockReceiveCubit cubit;

  setUp(() {
    cubit = MockReceiveCubit();
    if (sl.isRegistered<ReceiveCubit>()) sl.unregister<ReceiveCubit>();
    sl.registerFactory<ReceiveCubit>(() => cubit);
  });

  tearDown(() => sl.reset());

  Future<void> pump(WidgetTester tester, MutationState state) async {
    whenListen(cubit, const Stream<MutationState>.empty(),
        initialState: state);
    await tester
        .pumpWidget(const MaterialApp(home: ReceiveScreen(args: _args)));
    await tester.pump();
  }

  testWidgets('editing shows the form fields', (tester) async {
    await pump(tester, const MutationState());
    expect(find.byKey(const Key('receive_bin')), findsOneWidget);
    expect(find.byKey(const Key('receive_qty')), findsOneWidget);
    expect(find.byKey(const Key('mutation_submit')), findsOneWidget);
  });

  testWidgets('validation message is surfaced', (tester) async {
    await pump(
      tester,
      const MutationState(validationMessage: 'Choose a destination bin.'),
    );
    expect(find.byKey(const Key('mutation_validation')), findsOneWidget);
  });

  testWidgets('committed-offline outcome shows the queued banner',
      (tester) async {
    await pump(
      tester,
      MutationState(phase: MutationPhase.done, result: _queued()),
    );
    expect(find.byKey(const Key('outcome_queued')), findsOneWidget);
    expect(find.text('Committed offline'), findsOneWidget);
  });

  testWidgets('tapping submit calls the cubit', (tester) async {
    when(() => cubit.submit(
          inventoryItemId: any(named: 'inventoryItemId'),
          destinationBinId: any(named: 'destinationBinId'),
          quantity: any(named: 'quantity'),
        )).thenAnswer((_) async {});
    await pump(tester, const MutationState());

    await tester.enterText(find.byKey(const Key('receive_qty')), '5');
    await tester.tap(find.byKey(const Key('mutation_submit')));
    await tester.pump();

    verify(() => cubit.submit(
          inventoryItemId: 'item-1',
          destinationBinId: any(named: 'destinationBinId'),
          quantity: 5,
        )).called(1);
  });
}
