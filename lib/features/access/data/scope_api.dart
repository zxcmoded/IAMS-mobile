import 'package:dio/dio.dart';

import '../../../core/network/api_call.dart';
import 'models/scope.dart';

/// Typed client for `GET /api/me/scope`. Uses the *authenticated* Dio, so the
/// Bearer token is attached and a 401 invalidates the stored session (driving
/// the user back to re-activation). The call is routed through [unwrapApiErrors]
/// so a Dio failure surfaces as the flat [ApiException] `ScopeCubit` catches —
/// not the [DioException] Dio itself throws.
class ScopeApi {
  ScopeApi(this._dio);

  final Dio _dio;

  /// `GET /me/scope` — the caller's Company, role, and assigned Locations.
  Future<Scope> getScope() => unwrapApiErrors(() async {
        final res = await _dio.get<Map<String, dynamic>>('/me/scope');
        return Scope.fromJson(res.data!);
      });
}
