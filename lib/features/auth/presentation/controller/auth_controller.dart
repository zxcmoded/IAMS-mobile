import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/session_refresher.dart';
import '../../../../core/storage/token_store.dart';
import '../../data/auth_repository.dart';
import '../../data/models/auth_session.dart';
import 'auth_state.dart';

/// The single source of truth for the auth session and its lifecycle.
///
/// * Persists/loads the session via [TokenStore].
/// * Implements [SessionRefresher] so the [AuthInterceptor] can refresh on 401
///   without depending on presentation code.
/// * Coalesces concurrent refreshes onto one in-flight request.
class AuthController extends Cubit<AuthState> implements SessionRefresher {
  AuthController({
    required this._repository,
    required this._tokenStore,
  }) : super(const AuthState.unknown());

  final AuthRepository _repository;
  final TokenStore _tokenStore;

  Future<AuthSession>? _refreshInFlight;

  @override
  AuthSession? get currentSession => state.session;

  /// Called once at startup to restore any persisted session.
  Future<void> bootstrap() async {
    final session = await _tokenStore.read();
    if (session == null) {
      emit(const AuthState(status: AuthStatus.unauthenticated));
      return;
    }
    // If the refresh token itself is expired there is nothing to restore.
    if (DateTime.now().toUtc().isAfter(session.refreshTokenExpiresAt)) {
      await _tokenStore.clear();
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

  /// User-initiated sign-out. Best-effort server revoke, always clears locally.
  Future<void> logout() async {
    final session = state.session;
    if (session != null) {
      try {
        await _repository.logout(
          accessTokenHeader: session.authorizationHeader,
          refreshToken: session.refreshToken,
        );
      } catch (_) {
        // Logout is idempotent server-side; never block local sign-out on it.
      }
    }
    await _tokenStore.clear();
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  /// Dismiss the Session Expired screen and return to the Login flow.
  void acknowledgeSessionExpired() {
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  @override
  Future<AuthSession> refresh() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<AuthSession> _doRefresh() async {
    final current = state.session;
    if (current == null) {
      _toSessionExpired();
      throw const ApiException(
        code: ApiErrorCode.sessionExpired,
        message: 'Your session has expired. Please sign in again.',
      );
    }
    try {
      final refreshed = await _repository.refresh(current.refreshToken);
      await _tokenStore.write(refreshed);
      emit(AuthState(status: AuthStatus.authenticated, session: refreshed));
      return refreshed;
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        _toSessionExpired();
      }
      rethrow;
    }
  }

  void _toSessionExpired() {
    // Keep the (now unusable) session reference out of state; the UI only needs
    // to know a re-auth is required.
    unawaited(_tokenStore.clear());
    emit(const AuthState(status: AuthStatus.sessionExpired));
  }
}
