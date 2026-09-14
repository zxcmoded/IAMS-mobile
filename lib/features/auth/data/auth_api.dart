import 'package:dio/dio.dart';

import 'models/auth_session.dart';

/// Typed client for the auth endpoints. Uses the *raw* Dio (no auth
/// interceptor) so a 401/403 here is never auto-refreshed/retried. All
/// methods throw [ApiException] (mapped by the ErrorInterceptor) on failure.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  /// `POST /auth/activate` — the sole authentication entry point. Validates
  /// the Activation Key, enforces single-device binding, and issues a fresh
  /// session on success. Anonymous, rate-limited per client IP.
  Future<AuthSession> activate({
    required String activationKey,
    required String deviceId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/activate',
      data: {
        'activationKey': activationKey,
        'deviceId': deviceId,
      },
    );
    return AuthSession.fromJson(res.data!);
  }

  /// `POST /auth/refresh` — rotates the refresh token for a fresh session.
  /// A 401 here surfaces as `session_expired`.
  Future<AuthSession> refresh({
    required String refreshToken,
    String? deviceId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {
        'refreshToken': refreshToken,
        'deviceId': ?deviceId,
      },
    );
    return AuthSession.fromJson(res.data!);
  }

  /// `POST /auth/logout` — revokes the refresh token (idempotent, Bearer).
  /// Sent through the raw client with an explicit Authorization header so it
  /// is never caught in a refresh loop.
  Future<void> logout({
    required String accessTokenHeader,
    required String refreshToken,
  }) async {
    await _dio.post<void>(
      '/auth/logout',
      data: {'refreshToken': refreshToken},
      options: Options(headers: {'Authorization': accessTokenHeader}),
    );
  }
}
