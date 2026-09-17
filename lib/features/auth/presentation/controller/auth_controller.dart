import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/session_provider.dart';
import '../../../../core/storage/remembered_activation_key_store.dart';
import '../../../../core/storage/token_store.dart';
import '../../data/auth_repository.dart';
import '../../data/models/auth_session.dart';
import 'auth_state.dart';

/// The single source of truth for the auth session and its lifecycle.
///
/// * Persists/loads the session via [TokenStore].
/// * Implements [SessionProvider] so the [AuthInterceptor] can read the current
///   session for the Bearer header and signal invalidation on a 401.
///
/// There is no token refresh: an activation issues a permanent per-device
/// token that is stored once and reused indefinitely. A device is signed out
/// only by a user-initiated [logout] or by the server rejecting the token
/// (a 401 on an authenticated request → [invalidateSession]).
class AuthController extends Cubit<AuthState> implements SessionProvider {
  AuthController({
    required this._repository,
    required this._tokenStore,
    required this._rememberedKeyStore,
  }) : super(const AuthState.unknown());

  final AuthRepository _repository;
  final TokenStore _tokenStore;
  final RememberedActivationKeyStore _rememberedKeyStore;

  @override
  AuthSession? get currentSession => state.session;

  /// Called once at startup to restore any persisted session. The stored token
  /// is reused as-is; if it is no longer accepted the first authenticated
  /// request will 401 and trigger [invalidateSession].
  Future<void> bootstrap() async {
    final session = await _tokenStore.read();
    if (session == null) {
      emit(const AuthState(status: AuthStatus.unauthenticated));
      return;
    }
    emit(AuthState(status: AuthStatus.authenticated, session: session));
  }

  /// Persist and activate a session obtained from Activation Key entry.
  Future<void> onAuthenticated(AuthSession session) async {
    await _tokenStore.write(session);
    emit(AuthState(status: AuthStatus.authenticated, session: session));
  }

  /// User-initiated sign-out. Logout is audit-only server-side (it does not
  /// invalidate the token), so the client owns the actual sign-out: always
  /// clear the stored session regardless of the server's response.
  ///
  /// Deliberately does **not** clear the remembered Activation Key — a normal
  /// logout on an activated device should let the user resume with one tap
  /// (they land back on the Activation screen's "Welcome back" state). Use
  /// [logoutAndForget] for the shared/kiosk case.
  Future<void> logout() async {
    await _signOut();
  }

  /// Sign out *and* forget the remembered Activation Key, so the next user of
  /// this device must enter a key from scratch (shared/kiosk hand-off).
  Future<void> logoutAndForget() async {
    await _rememberedKeyStore.clear();
    await _signOut();
  }

  Future<void> _signOut() async {
    final session = state.session;
    if (session != null) {
      try {
        await _repository.logout(
          accessTokenHeader: session.authorizationHeader,
        );
      } catch (_) {
        // Best-effort audit call; never block local sign-out on it.
      }
    }
    await _tokenStore.clear();
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  /// The stored token was rejected by the API (401). Clear it and surface the
  /// Session Expired screen so the user re-activates. Safe to call when already
  /// signed out — a no-op in that case.
  @override
  void invalidateSession() {
    if (state.status == AuthStatus.unauthenticated ||
        state.status == AuthStatus.sessionExpired) {
      return;
    }
    unawaited(_tokenStore.clear());
    emit(const AuthState(status: AuthStatus.sessionExpired));
  }

  /// Dismiss the Session Expired screen and return to the activation flow.
  void acknowledgeSessionExpired() {
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }
}
