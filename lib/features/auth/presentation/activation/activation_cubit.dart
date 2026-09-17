import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/storage/remembered_activation_key_store.dart';
import '../../data/auth_repository.dart';
import '../../data/models/auth_session.dart';

enum ActivationStatus { idle, resume, activating, error, terminal, activated }

/// State for the Activation Key screen — the sole entry point to
/// authentication now that login/2FA are gone.
///
/// [ActivationStatus.resume] is the "Welcome back" state: this device has a
/// remembered Activation Key, so the screen offers a one-tap continue instead
/// of the blank entry form. The user can still fall back to manual entry.
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
  bool get isResume => status == ActivationStatus.resume;

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
  ActivationCubit(this._repository, this._rememberedKeyStore)
      : super(const ActivationState());

  final AuthRepository _repository;
  final RememberedActivationKeyStore _rememberedKeyStore;

  /// The raw key backing the current [ActivationStatus.resume] state, held so
  /// [resume] can re-submit it without the UI having to round-trip it.
  String? _rememberedKey;

  /// Called once when the screen mounts. If this device has a remembered
  /// Activation Key, enter the "Welcome back" resume state; otherwise stay on
  /// the blank entry form. A no-op if we've already moved past [idle] (e.g. an
  /// in-flight activation), so it never clobbers a live submission.
  Future<void> loadRemembered() async {
    if (state.status != ActivationStatus.idle) return;
    final remembered = await _rememberedKeyStore.read();
    if (remembered == null || remembered.isEmpty) return;
    if (state.status != ActivationStatus.idle) return;
    _rememberedKey = remembered;
    emit(state.copyWith(status: ActivationStatus.resume));
  }

  /// One-tap continue from the resume state: re-activate with the remembered
  /// key. If it fails the key is forgotten and the user falls back to manual
  /// entry (see [submit]).
  Future<void> resume() async {
    final key = _rememberedKey;
    if (key == null || key.isEmpty) return;
    await submit(activationKey: key, isResume: true);
  }

  /// Abandon the remembered key and show the blank entry form. Used for the
  /// "use a different activation key" / "forget this device" case (the key
  /// belongs to someone else, or a shared/kiosk device is being handed off).
  Future<void> useDifferentKey() async {
    _rememberedKey = null;
    await _rememberedKeyStore.clear();
    emit(const ActivationState());
  }

  Future<void> submit({
    required String activationKey,
    bool isResume = false,
  }) async {
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
      // Remember the raw key the user actually typed so a future launch can
      // resume with one tap — the server never echoes the key back.
      await _rememberedKeyStore.write(trimmed);
      emit(ActivationState(status: ActivationStatus.activated, session: session));
    } on ApiException catch (e) {
      // A remembered key that no longer works (deactivated account, admin
      // reset that unbound the device, etc.) must not strand the user on a
      // broken one-tap resume: forget it so they fall back to manual entry
      // with the mapped error explaining why. `no_active_company` is the one
      // exception — it means the account isn't linked to a company yet, not
      // that the key itself is invalid, so the key is still good and should
      // be kept for when an admin fixes the company link.
      if (isResume && e.code != ApiErrorCode.noActiveCompany) {
        _rememberedKey = null;
        await _rememberedKeyStore.clear();
      }
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
      if (isResume) {
        _rememberedKey = null;
        await _rememberedKeyStore.clear();
      }
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
