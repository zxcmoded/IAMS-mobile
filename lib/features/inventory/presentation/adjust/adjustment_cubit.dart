import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/outbox_repository.dart';
import '../shared/mutation_state.dart';

/// F4 Adjustment: a signed, non-zero quantity delta with a required reason. The
/// result must stay >= 0 — pre-checked client-side for UX; the server's
/// `422 insufficient_stock` is the backstop.
class AdjustmentCubit extends Cubit<MutationState> {
  AdjustmentCubit(this._outbox) : super(const MutationState());

  final OutboxRepository _outbox;

  Future<void> submit({
    required String inventoryItemId,
    required String? binId,
    required double? quantityDelta,
    required String reason,
    required double? binOnHand,
  }) async {
    if (state.isSubmitting) return;

    final error = _validate(binId, quantityDelta, reason, binOnHand);
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
    final result = await _outbox.adjust(
      inventoryItemId: inventoryItemId,
      binId: binId!,
      quantityDelta: quantityDelta!,
      reason: reason.trim(),
    );
    emit(state.copyWith(phase: MutationPhase.done, result: result));
  }

  String? _validate(
    String? binId,
    double? quantityDelta,
    String reason,
    double? binOnHand,
  ) {
    if (binId == null || binId.isEmpty) return 'Choose a bin.';
    if (quantityDelta == null || quantityDelta == 0) {
      return 'Enter a non-zero adjustment.';
    }
    if (reason.trim().isEmpty) return 'A reason is required.';
    if (binOnHand != null && binOnHand + quantityDelta < 0) {
      return 'Adjustment would drive the bin below zero '
          '(on hand ${_fmt(binOnHand)}).';
    }
    return null;
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}
