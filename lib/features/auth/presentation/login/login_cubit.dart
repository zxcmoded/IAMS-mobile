import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/auth_repository.dart';
import '../../data/models/auth_challenge.dart';

enum LoginStatus { idle, validating, error, challengeIssued }

/// State for the Login screen. Mirrors the spec's idle / validating / error
/// states. `locked` from the contract is surfaced through [errorCode] rather
/// than a bespoke state (lockout UI is Not Specified — we only avoid crashing).
class LoginState extends Equatable {
  const LoginState({
    this.status = LoginStatus.idle,
    this.errorCode,
    this.errorMessage,
    this.fieldErrors = const {},
    this.challenge,
  });

  final LoginStatus status;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, List<String>> fieldErrors;

  /// Set on success; the screen navigates to the 2FA challenge with this.
  final AuthChallenge? challenge;

  bool get isBusy => status == LoginStatus.validating;

  /// Sentinel distinguishing "argument omitted" (preserve) from an explicit
  /// `null` (clear). Keeps error fields from being silently wiped by a
  /// `copyWith` that only means to change something else.
  static const Object _unset = Object();

  LoginState copyWith({
    LoginStatus? status,
    Object? errorCode = _unset,
    Object? errorMessage = _unset,
    Map<String, List<String>>? fieldErrors,
    AuthChallenge? challenge,
  }) =>
      LoginState(
        status: status ?? this.status,
        errorCode: identical(errorCode, _unset)
            ? this.errorCode
            : errorCode as String?,
        errorMessage: identical(errorMessage, _unset)
            ? this.errorMessage
            : errorMessage as String?,
        fieldErrors: fieldErrors ?? this.fieldErrors,
        challenge: challenge ?? this.challenge,
      );

  @override
  List<Object?> get props =>
      [status, errorCode, errorMessage, fieldErrors, challenge];
}

class LoginCubit extends Cubit<LoginState> {
  LoginCubit(this._repository) : super(const LoginState());

  final AuthRepository _repository;

  Future<void> submit({
    required String username,
    required String password,
  }) async {
    if (state.isBusy) return;

    // Local validation before hitting the network.
    final localErrors = <String, List<String>>{};
    if (username.trim().isEmpty) {
      localErrors['Username'] = ['Enter your username.'];
    }
    if (password.isEmpty) {
      localErrors['Password'] = ['Enter your password.'];
    }
    if (localErrors.isNotEmpty) {
      emit(state.copyWith(
        status: LoginStatus.error,
        errorCode: null,
        errorMessage: null,
        fieldErrors: localErrors,
      ));
      return;
    }

    emit(const LoginState(status: LoginStatus.validating));
    try {
      final challenge = await _repository.login(
        username: username.trim(),
        password: password,
      );
      emit(LoginState(status: LoginStatus.challengeIssued, challenge: challenge));
    } on ApiException catch (e) {
      emit(LoginState(
        status: LoginStatus.error,
        errorCode: e.code,
        errorMessage: _messageFor(e),
        fieldErrors: e.errors,
      ));
    }
  }

  /// Clear a consumed challenge/error after navigation so returning to Login
  /// starts clean.
  void reset() => emit(const LoginState());

  String _messageFor(ApiException e) {
    switch (e.code) {
      case ApiErrorCode.invalidCredentials:
        return 'Incorrect username or password.';
      case ApiErrorCode.accountInactive:
        return 'This account is inactive. Contact your administrator.';
      case ApiErrorCode.twoFactorLocked:
        return 'Too many attempts. Please wait and try again.';
      case ApiErrorCode.network:
        return e.message;
      default:
        return e.message;
    }
  }
}
