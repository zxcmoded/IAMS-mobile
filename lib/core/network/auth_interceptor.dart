import 'package:dio/dio.dart';

import 'session_provider.dart';

/// Attaches the Bearer token to outgoing requests and, on a 401, treats the
/// stored token as no longer valid.
///
/// There is no token refresh: an activation issues a permanent per-device
/// token, so a 401 cannot be recovered by a refresh-and-retry. It means the
/// server has rejected the stored token (e.g. an admin reset the activation
/// key), and the only recovery is re-activation. The interceptor signals
/// [SessionProvider.invalidateSession] — which clears local auth and drives the
/// app to the Session Expired screen — then forwards the original error.
///
/// Only mounted on the *authenticated* Dio instance. The auth endpoints
/// (activate/logout) use a separate raw Dio and must never be intercepted here.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._sessionProvider);

  final SessionProvider _sessionProvider;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final session = _sessionProvider.currentSession;
    if (session != null) {
      options.headers['Authorization'] = session.authorizationHeader;
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      _sessionProvider.invalidateSession();
    }
    handler.next(err);
  }
}
