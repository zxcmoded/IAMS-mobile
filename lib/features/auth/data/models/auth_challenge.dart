import 'package:equatable/equatable.dart';

/// Response to `POST /api/auth/login` and `POST /api/auth/2fa/resend`.
///
/// Login never returns tokens — it always opens a 2FA challenge. The client
/// carries [challengeToken] to the verify/resend calls.
class AuthChallenge extends Equatable {
  const AuthChallenge({
    required this.challengeToken,
    required this.expiresInSeconds,
    required this.resendAvailableInSeconds,
    this.devOtp,
  });

  final String challengeToken;

  /// Seconds until the OTP window elapses (drives the restart-login prompt).
  final int expiresInSeconds;

  /// Seconds until "resend" is allowed again (drives the resend cooldown).
  final int resendAvailableInSeconds;

  /// Non-production only: the actual OTP so the app can be tested end to end.
  /// `null` in Production.
  final String? devOtp;

  factory AuthChallenge.fromJson(Map<String, dynamic> json) => AuthChallenge(
        challengeToken: json['challengeToken'] as String,
        expiresInSeconds: (json['expiresInSeconds'] as num).toInt(),
        resendAvailableInSeconds:
            (json['resendAvailableInSeconds'] as num).toInt(),
        devOtp: json['devOtp'] as String?,
      );

  @override
  List<Object?> get props =>
      [challengeToken, expiresInSeconds, resendAvailableInSeconds, devOtp];
}
