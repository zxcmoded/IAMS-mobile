import 'package:dio/dio.dart';

import 'models/access.dart';
import 'models/scope.dart';

/// Typed client for the F1/F15 scope + access endpoints. Uses the
/// *authenticated* Dio, so the Bearer token is attached and a 401 triggers the
/// refresh-on-401 flow automatically.
class TenantApi {
  TenantApi(this._dio);

  final Dio _dio;

  /// `GET /me/scope` — the caller's active tenant/company/location plus every
  /// connection with its permission and hierarchy scope.
  Future<Scope> getScope() async {
    final res = await _dio.get<Map<String, dynamic>>('/me/scope');
    return Scope.fromJson(res.data!);
  }

  /// `POST /access/evaluate` — evaluate a single resource before offering an
  /// affordance (allowed / read-only / denied).
  Future<AccessDecision> evaluate(AccessRequest request) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/access/evaluate',
      data: request.toJson(),
    );
    return AccessDecision.fromJson(res.data!);
  }
}
