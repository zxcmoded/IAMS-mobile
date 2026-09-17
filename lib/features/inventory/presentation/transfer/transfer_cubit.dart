import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/outbox_repository.dart';
import '../shared/mutation_state.dart';

/// F4 Transfer: move quantity of a SKU from a source bin to a destination bin.
/// Client-side pre-checks (positive qty, differing bins, not over source) are
/// UX guards only — the server's `400`/`422` are the real backstops.
class TransferCubit extends Cubit<MutationState> {
  TransferCubit(this._outbox) : super(const MutationState());

  final OutboxRepository _outbox;

  Future<void> submit({
    required String inventoryItemId,
    required String? sourceBinId,
    required String? destinationBinId,
    required double? quantity,
    required double? sourceOnHand,
  }) async {
    if (state.isSubmitting) return;

    final error =
        _validate(sourceBinId, destinationBinId, quantity, sourceOnHand);
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
    final result = await _outbox.transfer(
      inventoryItemId: inventoryItemId,
      sourceBinId: sourceBinId!,
      destinationBinId: destinationBinId!,
      quantity: quantity!,
    );
    emit(state.copyWith(phase: MutationPhase.done, result: result));
  }

  String? _validate(
    String? sourceBinId,
    String? destinationBinId,
    double? quantity,
    double? sourceOnHand,
  ) {
    if (sourceBinId == null || sourceBinId.isEmpty) {
      return 'Choose a source bin.';
    }
    if (destinationBinId == null || destinationBinId.isEmpty) {
      return 'Choose a destination bin.';
    }
    if (sourceBinId == destinationBinId) {
      return 'Source and destination bins must be different.';
    }
    if (quantity == null || quantity <= 0) {
      return 'Enter a quantity greater than zero.';
    }
    // Client-side over-source guard for fast feedback; the server's
    // `422 insufficient_stock` remains the authority (another device may have
    // drawn the bin down since we last observed it).
    if (sourceOnHand != null && quantity > sourceOnHand) {
      return 'Only ${_fmt(sourceOnHand)} available in the source bin.';
    }
    return null;
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}
