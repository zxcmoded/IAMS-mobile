import 'package:dio/dio.dart';

import '../../../core/network/api_call.dart';
import 'models/access.dart';
import 'models/scope.dart';

/// Typed client for the F1/F15 scope + access endpoints. Uses the
/// *authenticated* Dio, so the Bearer token is attached and a 401 invalidates
/// the stored session (driving the user back to re-activation). Every call is
/// routed through [unwrapApiErrors] so a Dio failure surfaces as the flat
/// [ApiException] `ScopeCubit`/`AccessCubit` catch — not the [DioException]
/// Dio itself throws.
class TenantApi {
  TenantApi(this._dio);

  final Dio _dio;

  /// `GET /me/scope` — the caller's active tenant/company/location plus every
  /// connection with its permission and hierarchy scope.
  Future<Scope> getScope() => unwrapApiErrors(() async {
        final res = await _dio.get<Map<String, dynamic>>('/me/scope');
        return Scope.fromJson(res.data!);
      });

  /// `POST /access/evaluate` — evaluate a single resource before offering an
  /// affordance (allowed / read-only / denied).
  Future<AccessDecision> evaluate(AccessRequest request) =>
      unwrapApiErrors(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/access/evaluate',
          data: request.toJson(),
        );
        return AccessDecision.fromJson(res.data!);
      });
}
