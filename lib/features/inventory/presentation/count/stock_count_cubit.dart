import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/outbox_repository.dart';
import '../shared/mutation_state.dart';

/// F4 Stock Count: record a counted quantity for one bin. The variance and
/// whether it auto-applies or parks for approval are **server-computed** — this
/// cubit never computes variance client-side; it submits the count and the
/// screen renders the returned outcome (within-threshold vs PendingApproval).
class StockCountCubit extends Cubit<MutationState> {
  StockCountCubit(this._outbox) : super(const MutationState());

  final OutboxRepository _outbox;

  Future<void> submit({
    required String inventoryItemId,
    required String? binId,
    required double? countedQuantity,
  }) async {
    if (state.isSubmitting) return;

    final error = _validate(binId, countedQuantity);
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
    final result = await _outbox.count(
      inventoryItemId: inventoryItemId,
      binId: binId!,
      countedQuantity: countedQuantity!,
    );
    emit(state.copyWith(phase: MutationPhase.done, result: result));
  }

  String? _validate(String? binId, double? countedQuantity) {
    if (binId == null || binId.isEmpty) return 'Choose a bin to count.';
    if (countedQuantity == null || countedQuantity < 0) {
      return 'Enter a counted quantity of zero or more.';
    }
    return null;
  }
}
