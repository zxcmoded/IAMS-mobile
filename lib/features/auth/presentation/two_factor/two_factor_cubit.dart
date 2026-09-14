import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/auth_repository.dart';
import '../../data/models/auth_challenge.dart';
import '../../data/models/auth_session.dart';

enum TwoFactorStatus { idle, verifying, error, verified, expired }

/// State for the 2FA Challenge screen. Tracks the live challenge token (rotates
/// on resend), a resend cooldown countdown, and the verify result.
class TwoFactorState extends Equatable {
  const TwoFactorState({
    required this.challengeToken,
    this.status = TwoFactorStatus.idle,
    this.errorCode,
    this.errorMessage,
    this.resendCooldownSeconds = 0,
    this.isResending = false,
    this.devOtp,
    this.session,
  });

  final String challengeToken;
  final TwoFactorStatus status;
  final String? errorCode;
  final String? errorMessage;

  /// Seconds until resend is allowed; 0 means resend is available now.
  final int resendCooldownSeconds;
  final bool isResending;

  /// Non-production OTP echoed by the backend for testing; null in prod.
  final String? devOtp;

  /// Set on successful verify — the screen hands this to the AuthController.
  final AuthSession? session;

  bool get isVerifying => status == TwoFactorStatus.verifying;
  bool get canResend => resendCooldownSeconds <= 0 && !isResending;

  /// Sentinel distinguishing "argument omitted" (preserve current value) from
  /// an explicit `null` (clear the field). Without this, a bare `copyWith`
  /// call — e.g. the per-second cooldown tick — would silently wipe error
  /// fields it never meant to touch.
  static const Object _unset = Object();

  TwoFactorState copyWith({
    String? challengeToken,
    TwoFactorStatus? status,
    Object? errorCode = _unset,
    Object? errorMessage = _unset,
    int? resendCooldownSeconds,
    bool? isResending,
    String? devOtp,
    AuthSession? session,
  }) =>
      TwoFactorState(
        challengeToken: challengeToken ?? this.challengeToken,
        status: status ?? this.status,
        errorCode: identical(errorCode, _unset)
            ? this.errorCode
            : errorCode as String?,
        errorMessage: identical(errorMessage, _unset)
            ? this.errorMessage
            : errorMessage as String?,
        resendCooldownSeconds:
            resendCooldownSeconds ?? this.resendCooldownSeconds,
        isResending: isResending ?? this.isResending,
        devOtp: devOtp ?? this.devOtp,
        session: session ?? this.session,
      );

  @override
  List<Object?> get props => [
        challengeToken,
        status,
        errorCode,
        errorMessage,
        resendCooldownSeconds,
        isResending,
        devOtp,
        session,
      ];
}

class TwoFactorCubit extends Cubit<TwoFactorState> {
  TwoFactorCubit(this._repository, AuthChallenge challenge)
      : super(TwoFactorState(
          challengeToken: challenge.challengeToken,
          resendCooldownSeconds: challenge.resendAvailableInSeconds,
          devOtp: challenge.devOtp,
        )) {
    _startCooldown(challenge.resendAvailableInSeconds);
  }

  final AuthRepository _repository;
  Timer? _cooldownTimer;

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    emit(state.copyWith(resendCooldownSeconds: seconds));
    if (seconds <= 0) return;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = state.resendCooldownSeconds - 1;
      if (next <= 0) {
        timer.cancel();
        emit(state.copyWith(resendCooldownSeconds: 0));
      } else {
        emit(state.copyWith(resendCooldownSeconds: next));
      }
    });
  }

  Future<void> verify(String code) async {
    if (state.isVerifying) return;
    if (code.trim().isEmpty) {
      emit(state.copyWith(
        status: TwoFactorStatus.error,
        errorCode: null,
        errorMessage: 'Enter the verification code.',
      ));
      return;
    }
    // Clear any prior error as we start a fresh attempt.
    emit(state.copyWith(
      status: TwoFactorStatus.verifying,
      errorCode: null,
      errorMessage: null,
    ));
    try {
      final session = await _repository.verifyTwoFactor(
        challengeToken: state.challengeToken,
        code: code.trim(),
      );
      emit(state.copyWith(status: TwoFactorStatus.verified, session: session));
    } on ApiException catch (e) {
      // Terminal outcomes: the OTP can't be retried, so send the user back to
      // sign in. `no_active_company` is a valid 2FA but nothing to sign in to.
      final isTerminal = e.code == ApiErrorCode.twoFactorExpired ||
          e.code == ApiErrorCode.twoFactorLocked ||
          e.code == ApiErrorCode.notFound ||
          e.code == ApiErrorCode.noActiveCompany ||
          e.code == ApiErrorCode.deviceAlreadyRegistered;
      emit(state.copyWith(
        status: isTerminal ? TwoFactorStatus.expired : TwoFactorStatus.error,
        errorCode: e.code,
        errorMessage: _messageFor(e),
      ));
    }
  }

  Future<void> resend() async {
    if (!state.canResend) return;
    emit(state.copyWith(
      isResending: true,
      status: TwoFactorStatus.idle,
      errorCode: null,
      errorMessage: null,
    ));
    try {
      final challenge = await _repository.resendTwoFactor(state.challengeToken);
      emit(state.copyWith(
        challengeToken: challenge.challengeToken,
        devOtp: challenge.devOtp,
        isResending: false,
        status: TwoFactorStatus.idle,
        errorCode: null,
        errorMessage: null,
      ));
      _startCooldown(challenge.resendAvailableInSeconds);
    } on ApiException catch (e) {
      // resend_limit_reached is terminal (total cap hit) → send back to sign
      // in. resend_too_soon just surfaces the message and keeps the user here.
      final isTerminal = e.code == ApiErrorCode.resendLimitReached;
      emit(state.copyWith(
        isResending: false,
        status: isTerminal ? TwoFactorStatus.expired : TwoFactorStatus.error,
        errorCode: e.code,
        errorMessage: _messageFor(e),
      ));
    }
  }

  String _messageFor(ApiException e) {
    switch (e.code) {
      case ApiErrorCode.twoFactorInvalid:
        return 'That code is incorrect. Try again.';
      case ApiErrorCode.twoFactorExpired:
        return 'This code has expired. Please sign in again.';
      case ApiErrorCode.twoFactorLocked:
        return 'Too many incorrect attempts. Please sign in again.';
      case ApiErrorCode.resendTooSoon:
        return 'Please wait before requesting another code.';
      case ApiErrorCode.resendLimitReached:
        return 'Too many resend attempts. Please sign in again to restart.';
      case ApiErrorCode.rateLimited:
        return 'Too many attempts. Please wait a moment and try again.';
      case ApiErrorCode.notFound:
        return 'This challenge is no longer valid. Please sign in again.';
      case ApiErrorCode.noActiveCompany:
        return 'Your account isn\'t linked to a company yet. Contact your '
            'administrator, then sign in again.';
      case ApiErrorCode.deviceAlreadyRegistered:
        return 'This account is already registered to another device. '
            'Please contact your administrator to reset your device '
            'registration.';
      default:
        return e.message;
    }
  }

  @override
  Future<void> close() {
    _cooldownTimer?.cancel();
    return super.close();
  }
}
