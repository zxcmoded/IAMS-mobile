import 'package:dio/dio.dart';

import 'models/scan_result.dart';

/// Typed client for F3 scan resolution (`POST /api/scan/resolve`). Uses the
/// *authenticated* Dio so the Bearer token is attached and the shared
/// `ErrorInterceptor` normalizes any response ≥ 300 into a typed
/// `ApiException`. Tenant scope is resolved server-side off the JWT — never
/// sent by the client.
class ScanApi {
  ScanApi(this._dio);

  final Dio _dio;

  /// Resolves one raw code. [idempotencyKey] is optional on scan-resolve;
  /// replaying it returns the original outcome. The client stamps [rawCode]
  /// back onto the result so no-match/blocked states can echo the input.
  Future<ScanResult> resolve({
    required String rawCode,
    String? deviceId,
    DateTime? scannedAtUtc,
    String? idempotencyKey,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/scan/resolve',
      data: {
        'rawCode': rawCode,
        if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
        if (scannedAtUtc != null)
          'scannedAtUtc': scannedAtUtc.toUtc().toIso8601String(),
        if (idempotencyKey != null && idempotencyKey.isNotEmpty)
          'idempotencyKey': idempotencyKey,
      },
    );
    return ScanResult.fromJson(res.data!, rawCode: rawCode);
  }
}
