import 'package:dio/dio.dart';

import '../../../core/network/api_call.dart';
import 'models/auth_session.dart';

/// Typed client for the auth endpoints. Uses the *raw* Dio (no auth
/// interceptor) so a 401/403 here is never treated as an invalidated session.
/// All methods throw [ApiException] on failure — routed through
/// [unwrapApiErrors] so the [DioException] Dio itself throws never leaks past
/// this layer (see [unwrapApiErrors] for why that unwrap is needed even
/// though [ErrorInterceptor] already mapped the error).
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  /// `POST /auth/activate` — the sole authentication entry point. Validates
  /// the Activation Key, enforces single-device binding, and issues a fresh
  /// session on success. Anonymous, rate-limited per client IP.
  Future<AuthSession> activate({
    required String activationKey,
    required String deviceId,
  }) =>
      unwrapApiErrors(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/auth/activate',
          data: {
            'activationKey': activationKey,
            'deviceId': deviceId,
          },
        );
        return AuthSession.fromJson(res.data!);
      });

  /// `POST /auth/logout` — records a logout audit event (idempotent, 204 No
  /// Content). No request body; authenticated only by the Bearer header. This
  /// does *not* invalidate the token server-side — the client owns the actual
  /// sign-out by discarding its stored session regardless of the response.
  Future<void> logout({required String accessTokenHeader}) => unwrapApiErrors(
        () => _dio.post<void>(
          '/auth/logout',
          options: Options(headers: {'Authorization': accessTokenHeader}),
        ),
      );
}
