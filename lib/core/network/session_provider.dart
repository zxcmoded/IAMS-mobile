import '../../features/auth/data/models/auth_session.dart';

/// The contract the [AuthInterceptor] needs from whatever owns the auth session
/// (the AuthController). Kept as a narrow interface so the interceptor does not
/// depend on presentation code and stays unit-testable.
///
/// There is no token refresh: an activation issues a permanent per-device
/// token. The interceptor only reads the current session to attach the Bearer
/// header, and signals [invalidateSession] when the server rejects that token
/// (a 401 on an authenticated request) so the app can drive re-activation.
abstract class SessionProvider {
  /// The current session, if the user is signed in.
  AuthSession? get currentSession;

  /// Called when an authenticated request comes back 401 — the stored token is
  /// no longer accepted. Clears the stored session and transitions app auth
  /// state so the router sends the user back to re-activate. Idempotent and
  /// safe to call when already signed out.
  void invalidateSession();
}
