import 'package:equatable/equatable.dart';

import 'auth_user.dart';

/// AuthTokenResponse — returned by `2fa/verify` and `auth/refresh`.
/// This is the persisted session (tokens + expiries + user).
class AuthSession extends Equatable {
  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.user,
  });

  final String accessToken;
  final String tokenType;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final AuthUser user;

  /// The `Authorization` header value.
  String get authorizationHeader => '$tokenType $accessToken';

  /// True when the access token is at/near expiry (30s skew) — used to refresh
  /// proactively rather than waiting for a 401.
  bool isAccessTokenExpired({DateTime? now}) {
    final reference = (now ?? DateTime.now().toUtc());
    return reference
        .isAfter(accessTokenExpiresAt.subtract(const Duration(seconds: 30)));
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['accessToken'] as String,
        tokenType: (json['tokenType'] ?? 'Bearer') as String,
        accessTokenExpiresAt:
            DateTime.parse(json['accessTokenExpiresAt'] as String).toUtc(),
        refreshToken: json['refreshToken'] as String,
        refreshTokenExpiresAt:
            DateTime.parse(json['refreshTokenExpiresAt'] as String).toUtc(),
        user: AuthUser.fromJson(
            (json['user'] as Map).cast<String, dynamic>()),
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'tokenType': tokenType,
        'accessTokenExpiresAt': accessTokenExpiresAt.toIso8601String(),
        'refreshToken': refreshToken,
        'refreshTokenExpiresAt': refreshTokenExpiresAt.toIso8601String(),
        'user': user.toJson(),
      };

  @override
  List<Object?> get props => [
        accessToken,
        tokenType,
        accessTokenExpiresAt,
        refreshToken,
        refreshTokenExpiresAt,
        user,
      ];
}
