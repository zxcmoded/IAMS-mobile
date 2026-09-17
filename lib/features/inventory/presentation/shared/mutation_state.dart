import 'package:equatable/equatable.dart';

import '../../data/models/inventory_enums.dart';
import '../../data/outbox_repository.dart';

enum MutationPhase { editing, submitting, done }

/// Shared state for the four F4 mutation forms (receive / transfer / adjust /
/// count). Form field values live in the screen's own widget state (as with the
/// activation form) and are passed into the cubit's `submit`; this state only
/// tracks the submission lifecycle + a client-side [validationMessage] and the
/// server/queue [result].
class MutationState extends Equatable {
  const MutationState({
    this.phase = MutationPhase.editing,
    this.validationMessage,
    this.result,
  });

  final MutationPhase phase;

  /// Set when a client-side pre-check fails (non-positive qty, same-bin
  /// transfer, over-source, etc.) — a UX guard; the server error is the real
  /// backstop.
  final String? validationMessage;

  /// The outcome once a submit round-trips (or is queued offline).
  final MutationResult? result;

  bool get isSubmitting => phase == MutationPhase.submitting;
  bool get isDone => phase == MutationPhase.done;
  MutationOutcome? get outcome => result?.outcome;

  MutationState copyWith({
    MutationPhase? phase,
    Object? validationMessage = _unset,
    Object? result = _unset,
  }) =>
      MutationState(
        phase: phase ?? this.phase,
        validationMessage: identical(validationMessage, _unset)
            ? this.validationMessage
            : validationMessage as String?,
        result: identical(result, _unset) ? this.result : result as MutationResult?,
      );

  static const Object _unset = Object();

  @override
  List<Object?> get props => [phase, validationMessage, result];
}
