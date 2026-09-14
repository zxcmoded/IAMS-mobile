import 'package:dio/dio.dart';

import 'models/auth_challenge.dart';
import 'models/auth_session.dart';

/// Typed client for the F1 auth endpoints. Uses the *raw* Dio (no auth
/// interceptor) so a 401 here is never auto-refreshed/retried. All methods
/// throw [ApiException] (mapped by the ErrorInterceptor) on failure.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  /// `POST /auth/login` — verifies credentials and opens a 2FA challenge.
  Future<AuthChallenge> login({
    required String username,
    required String password,
    String? deviceId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'username': username,
        'password': password,
        'deviceId': ?deviceId,
      },
    );
    return AuthChallenge.fromJson(res.data!);
  }

  /// `POST /auth/2fa/verify` — exchanges the OTP for a session.
  Future<AuthSession> verifyTwoFactor({
    required String challengeToken,
    required String code,
    String? deviceId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/2fa/verify',
      data: {
        'challengeToken': challengeToken,
        'code': code,
        'deviceId': ?deviceId,
      },
    );
    return AuthSession.fromJson(res.data!);
  }

  /// `POST /auth/2fa/resend` — rotates the OTP and extends the window.
  Future<AuthChallenge> resendTwoFactor({
    required String challengeToken,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/2fa/resend',
      data: {'challengeToken': challengeToken},
    );
    return AuthChallenge.fromJson(res.data!);
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
