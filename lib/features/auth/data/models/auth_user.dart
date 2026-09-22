import 'package:equatable/equatable.dart';

import 'role.dart';

/// The authenticated user.
///
/// The `POST /auth/activate` response embeds the user with its [companyId] and
/// [role] (`{code,name}`); the `GET /me/scope` `user` object carries only the
/// identity fields (role + company are siblings there), so [companyId]/[role]
/// are nullable and simply absent in that context.
class AuthUser extends Equatable {
  const AuthUser({
    required this.id,
    required this.username,
    required this.displayName,
    this.companyId,
    this.role,
  });

  final String id;
  final String username;
  final String displayName;
  final String? companyId;
  final Role? role;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: (json['displayName'] ?? json['username']) as String,
        companyId: json['companyId'] as String?,
        role: json['role'] == null
            ? null
            : Role.fromJson((json['role'] as Map).cast<String, dynamic>()),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        if (companyId != null) 'companyId': companyId,
        if (role != null) 'role': role!.toJson(),
      };

  @override
  List<Object?> get props => [id, username, displayName, companyId, role];
}
