import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'error_interceptor.dart';

/// Builds the two Dio instances the app uses:
///
/// * [createRawClient] — no auth interceptor. Used by the auth endpoints
///   (login/verify/resend/refresh/logout) so a 401 there is never intercepted
///   and retried.
/// * [createAuthenticatedClient] — carries the Bearer token and refresh-on-401
///   behaviour (the [AuthInterceptor] is added by the DI wiring, which owns the
///   refresher, so this factory stays free of a construction cycle).
class DioFactory {
  const DioFactory._();

  static BaseOptions _baseOptions() => BaseOptions(
        baseUrl: '${AppConfig.apiBaseUrl}/api',
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: 'application/json',
        // We branch on ProblemDetails ourselves; let Dio raise for >=400 so the
        // error interceptor can map the body, but never treat 3xx as success.
        validateStatus: (status) => status != null && status >= 200 && status < 300,
        headers: const {'Accept': 'application/json'},
      );

  static Dio createRawClient() {
    final dio = Dio(_baseOptions());
    dio.interceptors.add(ErrorInterceptor());
    return dio;
  }

  static Dio createAuthenticatedClient() {
    final dio = Dio(_baseOptions());
    // ErrorInterceptor is added *last* so it maps errors the AuthInterceptor
    // chooses to forward. AuthInterceptor is inserted by the DI layer.
    dio.interceptors.add(ErrorInterceptor());
    return dio;
  }
}
