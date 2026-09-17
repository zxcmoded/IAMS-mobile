import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/auth_interceptor.dart';
import 'package:iams_mobile/core/network/session_provider.dart';
import 'package:iams_mobile/features/auth/data/models/auth_session.dart';

import '../support/fixtures.dart';

/// A hand-rolled [SessionProvider] fake — records invalidation and exposes a
/// swappable current session.
class FakeSessionProvider implements SessionProvider {
  FakeSessionProvider(this.currentSession);

  @override
  AuthSession? currentSession;

  int invalidations = 0;

  @override
  void invalidateSession() => invalidations++;
}

void main() {
  group('onRequest', () {
    test('attaches the Bearer header when a session exists', () {
      final provider = FakeSessionProvider(buildSession(accessToken: 'tok-1'));
      final interceptor = AuthInterceptor(provider);
      final options = RequestOptions(path: '/inventory/items');
      final handler = _RecordingRequestHandler();

      interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], 'Bearer tok-1');
      expect(handler.nextCalledWith, same(options));
    });

    test('sends no Authorization header when signed out', () {
      final provider = FakeSessionProvider(null);
      final interceptor = AuthInterceptor(provider);
      final options = RequestOptions(path: '/inventory/items');
      final handler = _RecordingRequestHandler();

      interceptor.onRequest(options, handler);

      expect(options.headers.containsKey('Authorization'), isFalse);
      expect(handler.nextCalledWith, same(options));
    });
  });

  group('onError', () {
    DioException errorWithStatus(int status) => DioException(
          requestOptions: RequestOptions(path: '/inventory/items'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/inventory/items'),
            statusCode: status,
          ),
        );

    test('a 401 invalidates the session and forwards the error', () {
      final provider = FakeSessionProvider(buildSession());
      final interceptor = AuthInterceptor(provider);
      final err = errorWithStatus(401);
      final handler = _RecordingErrorHandler();

      interceptor.onError(err, handler);

      expect(provider.invalidations, 1);
      expect(handler.nextCalledWith, same(err));
    });

    test('a non-401 error does not invalidate the session', () {
      final provider = FakeSessionProvider(buildSession());
      final interceptor = AuthInterceptor(provider);
      final err = errorWithStatus(500);
      final handler = _RecordingErrorHandler();

      interceptor.onError(err, handler);

      expect(provider.invalidations, 0);
      expect(handler.nextCalledWith, same(err));
    });

    test('a connection error (no response) does not invalidate', () {
      final provider = FakeSessionProvider(buildSession());
      final interceptor = AuthInterceptor(provider);
      final err = DioException(
        requestOptions: RequestOptions(path: '/inventory/items'),
        type: DioExceptionType.connectionError,
      );
      final handler = _RecordingErrorHandler();

      interceptor.onError(err, handler);

      expect(provider.invalidations, 0);
      expect(handler.nextCalledWith, same(err));
    });
  });
}

class _RecordingRequestHandler extends RequestInterceptorHandler {
  RequestOptions? nextCalledWith;

  @override
  void next(RequestOptions requestOptions) {
    nextCalledWith = requestOptions;
  }
}

class _RecordingErrorHandler extends ErrorInterceptorHandler {
  DioException? nextCalledWith;

  @override
  void next(DioException err) {
    nextCalledWith = err;
  }
}
