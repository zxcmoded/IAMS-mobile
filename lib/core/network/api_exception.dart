import 'package:equatable/equatable.dart';

/// Machine-readable error codes from the backend contract's RFC 7807
/// ProblemDetails `code` field. The UI branches on these — never on the
/// human-readable `title`/`detail` or on the HTTP status alone.
///
/// See: IAMS-backend/docs/api/F1-F15-auth-and-tenant-connections.md
class ApiErrorCode {
  const ApiErrorCode._();

  static const String validationFailed = 'validation_failed';
  static const String invalidCredentials = 'invalid_credentials';
  static const String accountInactive = 'account_inactive';
  static const String twoFactorInvalid = 'two_factor_invalid';
  static const String twoFactorExpired = 'two_factor_expired';
  static const String twoFactorLocked = 'two_factor_locked';
  static const String resendTooSoon = 'resend_too_soon';

  /// 429 from `2fa/resend`: the total resend cap for this challenge is hit
  /// (distinct from the `resend_too_soon` cooldown). Terminal — restart login.
  static const String resendLimitReached = 'resend_limit_reached';
  static const String sessionExpired = 'session_expired';

  /// 403 from `2fa/verify`: credentials + OTP were valid, but the user has no
  /// company membership to sign in to. Terminal — restart login.
  static const String noActiveCompany = 'no_active_company';
  static const String accessDenied = 'access_denied';
  static const String notFound = 'not_found';

  /// 403 from `2fa/verify`: credentials + OTP were valid, but this device's
  /// id doesn't match the device already bound to the account. The OTP
  /// challenge is consumed server-side when this happens — terminal, restart
  /// login. Reset requires an administrator; mobile has no self-service UI
  /// for it.
  static const String deviceAlreadyRegistered = 'device_already_registered';

  /// Synthetic code used when the failure is not an HTTP ProblemDetails
  /// response at all (socket error, timeout, DNS, TLS, etc.).
  static const String network = 'network_error';

  /// Synthetic code for a bodyless / unparseable 429 (e.g. IP rate limiting on
  /// login/2fa endpoints, which return a bare 429 with no ProblemDetails body).
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
