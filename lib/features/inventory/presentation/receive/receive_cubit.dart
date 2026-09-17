import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/outbox_repository.dart';
import '../shared/mutation_state.dart';

/// F4 Receiving: scan/select a SKU, quantity, destination bin. Offline-first —
/// commits locally and queues, surfacing the outcome via [MutationState].
class ReceiveCubit extends Cubit<MutationState> {
  ReceiveCubit(this._outbox) : super(const MutationState());

  final OutboxRepository _outbox;

  Future<void> submit({
    required String inventoryItemId,
    required String? destinationBinId,
    required double? quantity,
  }) async {
    if (state.isSubmitting) return;

    final error = _validate(destinationBinId, quantity);
    if (error != null) {
      emit(state.copyWith(
        phase: MutationPhase.editing,
        validationMessage: error,
      ));
      return;
    }

    emit(state.copyWith(
      phase: MutationPhase.submitting,
      validationMessage: null,
    ));
    final result = await _outbox.receive(
      inventoryItemId: inventoryItemId,
      destinationBinId: destinationBinId!,
      quantity: quantity!,
    );
    emit(state.copyWith(phase: MutationPhase.done, result: result));
  }

  String? _validate(String? binId, double? quantity) {
    if (binId == null || binId.isEmpty) return 'Choose a destination bin.';
    if (quantity == null || quantity <= 0) {
      return 'Enter a quantity greater than zero.';
    }
    return null;
  }
}
