import 'package:equatable/equatable.dart';

import '../../../auth/data/models/auth_user.dart';
import '../../../auth/data/models/role.dart';

/// A company reference (the caller's own Company).
class CompanyRef extends Equatable {
  const CompanyRef({required this.id, required this.name});

  final String id;
  final String name;

  factory CompanyRef.fromJson(Map<String, dynamic> json) => CompanyRef(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  @override
  List<Object?> get props => [id, name];
}

/// A location the caller may act within.
class LocationRef extends Equatable {
  const LocationRef({required this.id, required this.name});

  final String id;
  final String name;

  factory LocationRef.fromJson(Map<String, dynamic> json) => LocationRef(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  @override
  List<Object?> get props => [id, name];
}

/// The caller's effective scope — `GET /api/me/scope`.
///
/// A user always acts within their [company] and their full [assignedLocations]
/// set; there is no company-switcher or location-switcher. For Manager/User/
/// Viewer, [assignedLocations] is exactly their assigned set; for Admin/
/// SuperAdmin it is every Location in the Company.
class Scope extends Equatable {
  const Scope({
    required this.user,
    required this.role,
    required this.company,
    required this.assignedLocations,
    required this.unrestrictedCompanyAccess,
    required this.systemWideAccess,
  });

  final AuthUser user;
  final Role role;
  final CompanyRef company;
  final List<LocationRef> assignedLocations;

  /// `true` for Admin and SuperAdmin — sees every Location in the Company.
  final bool unrestrictedCompanyAccess;

  /// `true` only for SuperAdmin — not confined to a single Company.
  final bool systemWideAccess;

  /// Whether the caller is restricted to a specific assigned-Location set
  /// (Manager/User/Viewer) rather than the whole Company.
  bool get isLocationRestricted => !unrestrictedCompanyAccess;

  bool get hasAssignedLocations => assignedLocations.isNotEmpty;

  factory Scope.fromJson(Map<String, dynamic> json) => Scope(
        user: AuthUser.fromJson((json['user'] as Map).cast<String, dynamic>()),
        role: Role.fromJson((json['role'] as Map).cast<String, dynamic>()),
        company: CompanyRef.fromJson(
            (json['company'] as Map).cast<String, dynamic>()),
        assignedLocations: ((json['assignedLocations'] as List?) ?? const [])
            .map((e) => LocationRef.fromJson((e as Map).cast<String, dynamic>()))
            .toList(growable: false),
        unrestrictedCompanyAccess:
            json['unrestrictedCompanyAccess'] as bool? ?? false,
        systemWideAccess: json['systemWideAccess'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [
        user,
        role,
        company,
        assignedLocations,
        unrestrictedCompanyAccess,
        systemWideAccess,
      ];
}
