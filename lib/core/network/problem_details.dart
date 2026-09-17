import 'api_exception.dart';

/// Parses the backend's RFC 7807 ProblemDetails error bodies into a typed
/// [ApiException]. Kept separate from the Dio interceptor so it can be unit
/// tested against raw JSON without any HTTP machinery.
class ProblemDetailsParser {
  const ProblemDetailsParser._();

  /// Build an [ApiException] from a decoded response body ([data]) and the
  /// [statusCode]. Falls back to synthetic codes when the body is not a
  /// recognizable ProblemDetails document.
  static ApiException parse({
    required dynamic data,
    required int? statusCode,
  }) {
    if (data is Map) {
      final map = data.cast<String, dynamic>();
      final code = map['code'] as String?;
      final title = map['title'] as String?;
      final detail = map['detail'] as String?;
      final errors = _parseErrors(map['errors']);
      return ApiException(
        code: code ?? _fallbackCodeForStatus(statusCode),
        message: detail ?? title ?? _fallbackMessageForStatus(statusCode),
        statusCode: statusCode,
        errors: errors,
        traceId: map['traceId'] as String?,
        extensions: _parseExtensions(map),
      );
    }
    return ApiException(
      code: _fallbackCodeForStatus(statusCode),
      message: _fallbackMessageForStatus(statusCode),
      statusCode: statusCode,
    );
  }

  /// The RFC 7807 core members that are already surfaced as first-class
  /// [ApiException] fields — everything else on the body is an extension member
  /// (e.g. `conflicts`, `binId`, `availableQuantity`) and is kept verbatim.
  static const _standardMembers = {
    'type', 'title', 'status', 'detail', 'instance', 'code', 'errors',
    'traceId',
  };

  static Map<String, dynamic> _parseExtensions(Map<String, dynamic> map) {
    final ext = <String, dynamic>{};
    map.forEach((key, value) {
      if (!_standardMembers.contains(key)) ext[key] = value;
    });
    return ext;
  }

  static Map<String, List<String>> _parseErrors(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, List<String>>{};
    raw.forEach((key, value) {
      if (value is List) {
        result[key.toString()] =
            value.map((e) => e.toString()).toList(growable: false);
      } else if (value != null) {
        result[key.toString()] = [value.toString()];
      }
    });
    return result;
  }

  static String _fallbackCodeForStatus(int? status) {
    if (status == 429) return ApiErrorCode.rateLimited;
    return ApiErrorCode.unknown;
  }

  static String _fallbackMessageForStatus(int? status) {
    if (status == null) return 'Something went wrong. Please try again.';
    if (status == 429) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    return 'Request failed ($status). Please try again.';
  }
}
