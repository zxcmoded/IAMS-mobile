import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'session_refresher.dart';

/// Attaches the Bearer token to outgoing requests and, on a 401, attempts a
/// single token refresh then retries the original request. If refresh fails
/// (`session_expired`), the error is forwarded and the [SessionRefresher] is
/// responsible for driving the app to the Session Expired screen.
///
/// Only mounted on the *authenticated* Dio instance. The auth endpoints
/// (activate/refresh/logout) use a separate raw Dio and must never be
/// retried by this interceptor.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({required this._refresher, required this._retryClient});

  final SessionRefresher _refresher;

  /// A Dio used to replay the original request after a refresh. This is the
  /// same authenticated client; passed in to avoid a construction cycle.
  final Dio _retryClient;

  static const _retriedFlag = 'x-auth-retried';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final session = _refresher.currentSession;
    if (session != null) {
      options.headers['Authorization'] = session.authorizationHeader;
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final alreadyRetried = err.requestOptions.extra[_retriedFlag] == true;

    if (response?.statusCode != 401 || alreadyRetried) {
      handler.next(err);
      return;
    }

    try {
      final session = await _refresher.refresh();
      final options = err.requestOptions
        ..extra[_retriedFlag] = true
        ..headers['Authorization'] = session.authorizationHeader;
      final retried = await _retryClient.fetch<dynamic>(options);
      handler.resolve(retried);
    } on ApiException catch (e) {
      // Refresh failed (session_expired handled by the refresher's state
      // transition). Surface the original 401 as a typed error.
      handler.reject(err.copyWith(error: e));
    } catch (_) {
      handler.next(err);
    }
  }
}
