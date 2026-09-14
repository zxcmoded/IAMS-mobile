import 'package:equatable/equatable.dart';

/// Machine-readable error codes from the backend contract's RFC 7807
/// ProblemDetails `code` field. The UI branches on these — never on the
/// human-readable `title`/`detail` or on the HTTP status alone.
///
/// See: IAMS-backend/docs/api/activation-key-authentication.md
class ApiErrorCode {
  const ApiErrorCode._();

  static const String validationFailed = 'validation_failed';
  static const String sessionExpired = 'session_expired';

  /// 401 from `POST /api/auth/activate`: the activation key does not resolve
  /// to an active user. Deliberately the same code whether the key doesn't
  /// exist at all or belongs to a deactivated account — do not attempt to
  /// distinguish these cases in the UI beyond "that key isn't valid."
  static const String activationKeyInvalid = 'activation_key_invalid';

  /// 403 from `POST /api/auth/activate`: the key is valid but already bound
  /// to a device other than the one presenting it. Terminal — do not
  /// auto-retry. Recovery requires an administrator to reset the binding
  /// out-of-band (`POST /api/admin/users/{userId}/activation/reset`); mobile
  /// has no self-service UI for it.
  static const String activationKeyAlreadyBound =
      'activation_key_already_bound';

  /// 403 from `POST /api/auth/activate`: the key is valid and this device is
  /// now bound, but the user has no company membership to sign in to.
  /// Terminal — retrying activation won't help without admin intervention.
  static const String noActiveCompany = 'no_active_company';
  static const String accessDenied = 'access_denied';
  static const String notFound = 'not_found';

  /// Synthetic code used when the failure is not an HTTP ProblemDetails
  /// response at all (socket error, timeout, DNS, TLS, etc.).
  static const String network = 'network_error';

  /// Synthetic code for a bodyless / unparseable 429 (e.g. IP rate limiting
  /// on `/api/auth/activate`, which returns a bare 429 with no ProblemDetails
  /// body).
  static const String rateLimited = 'rate_limited';

  /// Synthetic code used when a response could not be parsed / was unexpected.
  static const String unknown = 'unknown_error';
}

/// A typed error raised by the network layer. Carries the parsed ProblemDetails
/// `code` so screens/cubits can render the correct state without string
/// matching. Field-level validation errors are exposed via [errors].
class ApiException extends Equatable implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.errors = const {},
    this.traceId,
  });

  /// Stable machine-readable code (see [ApiErrorCode]).
  final String code;

  /// Human-readable message suitable for a fallback error display.
  final String message;

  /// HTTP status code, when the failure came from a response.
  final int? statusCode;

  /// Field -> messages map from a 400 `validation_failed` response.
  final Map<String, List<String>> errors;

  /// Informational correlation id from ProblemDetails (support/debugging).
  /// Not used for branching; safe to surface in an error footer.
  final String? traceId;

  bool get isSessionExpired => code == ApiErrorCode.sessionExpired;
  bool get isNetwork => code == ApiErrorCode.network;

  @override
  String toString() =>
      'ApiException($code, status=$statusCode, "$message", traceId=$traceId)';

  @override
  List<Object?> get props => [code, message, statusCode, errors, traceId];
}
