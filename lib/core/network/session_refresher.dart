import '../../features/auth/data/models/auth_session.dart';

/// Contract the [AuthInterceptor] needs from whatever owns the auth session
/// (the AuthController). Kept as a narrow interface so the interceptor does not
/// depend on presentation code and stays unit-testable.
abstract class SessionRefresher {
  /// The current session, if the user is signed in.
  AuthSession? get currentSession;

  /// Exchange the stored refresh token for a fresh session.
  ///
  /// Coalesces concurrent callers onto a single in-flight refresh. On failure
  /// with `session_expired` it transitions app auth state to expired and
  /// rethrows the [ApiException] so the caller can surface it.
  Future<AuthSession> refresh();
}
