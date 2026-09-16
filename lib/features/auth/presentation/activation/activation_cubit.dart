import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/auth_repository.dart';
import '../../data/models/auth_session.dart';

enum ActivationStatus { idle, activating, error, terminal, activated }

/// State for the Activation Key screen — the sole entry point to
/// authentication now that login/2FA are gone.
///
/// [ActivationStatus.terminal] covers the two 403s that can't be fixed by
/// retrying the same key (`activation_key_already_bound`,
/// `no_active_company`) — the dedicated terminal UI tells the user to
/// contact an administrator and does not auto-retry.
class ActivationState extends Equatable {
  const ActivationState({
    this.status = ActivationStatus.idle,
    this.errorCode,
    this.errorMessage,
    this.fieldErrors = const {},
    this.session,
  });

  final ActivationStatus status;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, List<String>> fieldErrors;

  /// Set on success; the screen hands this to the AuthController.
  final AuthSession? session;

  bool get isBusy => status == ActivationStatus.activating;
  bool get isTerminal => status == ActivationStatus.terminal;

  /// Sentinel distinguishing "argument omitted" (preserve) from an explicit
  /// `null` (clear). Keeps error fields from being silently wiped by a
  /// `copyWith` that only means to change something else.
  static const Object _unset = Object();

  ActivationState copyWith({
    ActivationStatus? status,
    Object? errorCode = _unset,
    Object? errorMessage = _unset,
    Map<String, List<String>>? fieldErrors,
    AuthSession? session,
  }) =>
      ActivationState(
        status: status ?? this.status,
        errorCode: identical(errorCode, _unset)
            ? this.errorCode
            : errorCode as String?,
        errorMessage: identical(errorMessage, _unset)
            ? this.errorMessage
            : errorMessage as String?,
        fieldErrors: fieldErrors ?? this.fieldErrors,
        session: session ?? this.session,
      );

  @override
  List<Object?> get props =>
      [status, errorCode, errorMessage, fieldErrors, session];
}

class ActivationCubit extends Cubit<ActivationState> {
  ActivationCubit(this._repository) : super(const ActivationState());

  final AuthRepository _repository;

  Future<void> submit({required String activationKey}) async {
    if (state.isBusy) return;

    final trimmed = activationKey.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(
        status: ActivationStatus.error,
        errorCode: null,
        errorMessage: null,
        fieldErrors: const {
          'ActivationKey': ['Enter your activation key.'],
        },
      ));
      return;
    }

    emit(const ActivationState(status: ActivationStatus.activating));
    try {
      final session = await _repository.activate(trimmed);
      emit(ActivationState(status: ActivationStatus.activated, session: session));
    } on ApiException catch (e) {
      // Terminal outcomes: neither can be fixed by resubmitting the same
      // key, so the UI must not auto-retry — only a manual "try again" tap
      // (which just resets this cubit) re-opens the form.
      final isTerminal = e.code == ApiErrorCode.activationKeyAlreadyBound ||
          e.code == ApiErrorCode.noActiveCompany;
      emit(ActivationState(
        status: isTerminal ? ActivationStatus.terminal : ActivationStatus.error,
        errorCode: e.code,
        errorMessage: _messageFor(e),
        fieldErrors: e.errors,
      ));
    } catch (_) {
      // Catch-all for non-[ApiException] failures — e.g. a PlatformException
      // from secure storage (keystore/keychain) while reading the device id,
      // or a TypeError/FormatException parsing an unexpected activation
      // response. Without this the Future error would go unhandled and the
      // cubit would stay in [ActivationStatus.activating] forever (spinner
      // spins, no error shown). Surface a generic message rather than leaking
      // raw exception text to the UI; treat as retryable (non-terminal).
      emit(const ActivationState(
        status: ActivationStatus.error,
        errorCode: ApiErrorCode.unknown,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }

  /// Clear a consumed error/terminal state so the form starts fresh — used
  /// both after a successful hand-off and for the terminal state's manual
  /// "Try again" action.
  void reset() => emit(const ActivationState());

  String _messageFor(ApiException e) {
    switch (e.code) {
      case ApiErrorCode.activationKeyInvalid:
        return 'That activation key isn\'t valid. Check it and try again.';
      case ApiErrorCode.activationKeyAlreadyBound:
        return 'This activation key is already registered to another '
            'device. Please contact your administrator to reset it.';
      case ApiErrorCode.noActiveCompany:
        return 'Your account isn\'t linked to a company yet. Contact your '
            'administrator.';
      case ApiErrorCode.network:
        return e.message;
      default:
        return e.message;
    }
  }
}
