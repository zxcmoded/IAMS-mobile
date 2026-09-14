import 'package:equatable/equatable.dart';

/// The authenticated user, as embedded in AuthTokenResponse and /me/scope.
class AuthUser extends Equatable {
  const AuthUser({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final String id;
  final String username;
  final String displayName;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: (json['displayName'] ?? json['username']) as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
      };

  @override
  List<Object?> get props => [id, username, displayName];
}
