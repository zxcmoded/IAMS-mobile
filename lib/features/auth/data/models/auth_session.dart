import 'package:equatable/equatable.dart';

import 'auth_user.dart';

/// AuthTokenResponse — returned by `POST /auth/activate`. This is the persisted
/// session (permanent per-device access token + user).
///
/// There is no refresh token: one activation logs the device in for the life of
/// the token. [accessTokenExpiresAt] is a far-future, purely informational
/// timestamp from the backend — never schedule a refresh off it (there is no
/// refresh endpoint). A stored token stops working only when the server starts
/// rejecting it with a 401, which the network layer treats as "re-activate".
class AuthSession extends Equatable {
  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.accessTokenExpiresAt,
    required this.user,
  });

  final String accessToken;
  final String tokenType;
  final DateTime accessTokenExpiresAt;
  final AuthUser user;

  /// The `Authorization` header value.
  String get authorizationHeader => '$tokenType $accessToken';

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['accessToken'] as String,
        tokenType: (json['tokenType'] ?? 'Bearer') as String,
        accessTokenExpiresAt:
            DateTime.parse(json['accessTokenExpiresAt'] as String).toUtc(),
        user: AuthUser.fromJson(
            (json['user'] as Map).cast<String, dynamic>()),
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'tokenType': tokenType,
        'accessTokenExpiresAt': accessTokenExpiresAt.toIso8601String(),
        'user': user.toJson(),
      };

  @override
  List<Object?> get props => [
        accessToken,
        tokenType,
        accessTokenExpiresAt,
        user,
      ];
}
