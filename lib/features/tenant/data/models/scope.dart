import 'package:equatable/equatable.dart';

import '../../../auth/data/models/auth_user.dart';
import 'enums.dart';

/// A tenant reference (active tenant or a connection's target tenant).
///
/// Wire field is `kind` (`Parent` | `Child`) — the parent/child indicator.
class TenantRef extends Equatable {
  const TenantRef({required this.id, required this.name, required this.kind});

  final String id;
  final String name;
  final TenantType kind;

  factory TenantRef.fromJson(Map<String, dynamic> json) => TenantRef(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: TenantType.fromJson(json['kind'] as String?),
      );

  @override
  List<Object?> get props => [id, name, kind];
}

/// A company reference.
class CompanyRef extends Equatable {
  const CompanyRef({
    required this.id,
    required this.name,
    required this.tenantId,
  });

  final String id;
  final String name;
  final String tenantId;

  factory CompanyRef.fromJson(Map<String, dynamic> json) => CompanyRef(
        id: json['id'] as String,
        name: json['name'] as String,
        tenantId: json['tenantId'] as String,
      );

  @override
  List<Object?> get props => [id, name, tenantId];
}

/// A location reference. `activeLocation` may be null (whole-company scope).
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

/// One hierarchy node a connection grants, with the permission that applies at
/// that node (its own override, else the connection default).
class ConnectionScope extends Equatable {
  const ConnectionScope({
    required this.level,
    required this.nodeId,
    required this.permissionLevel,
  });

  final ScopeLevel level;

  /// The id of the node at [level]. For a `Company`-level scope this is the
  /// target company id (grants the whole company).
  final String? nodeId;

  /// The effective permission that applies at this node.
  final PermissionLevel permissionLevel;

  factory ConnectionScope.fromJson(Map<String, dynamic> json) =>
      ConnectionScope(
        level: ScopeLevel.fromJson(json['level'] as String?),
        nodeId: json['nodeId'] as String?,
        permissionLevel:
            PermissionLevel.fromJson(json['permissionLevel'] as String?),
      );

  @override
  List<Object?> get props => [level, nodeId, permissionLevel];
}

/// One configured connection from the caller's active company to a target.
///
/// A single connection can grant several hierarchy nodes ([scopes]), each with
/// its own effective permission; [permissionLevel] is the connection default.
class Connection extends Equatable {
  const Connection({
    required this.connectionId,
    required this.targetCompany,
    required this.targetTenant,
    required this.connectionType,
    required this.isEnabled,
    required this.permissionLevel,
    required this.scopes,
    required this.policyVersion,
  });

  final String connectionId;
  final CompanyRef targetCompany;
  final TenantRef targetTenant;
  final ConnectionType connectionType;
  final bool isEnabled;

  /// Connection-level default permission. Per-scope permission is what applies
  /// to a given node (see [ConnectionScope.permissionLevel]).
  final PermissionLevel permissionLevel;

  /// One or more granted hierarchy nodes. Empty means the connection grants
  /// nothing yet.
  final List<ConnectionScope> scopes;
  final int policyVersion;

  /// The best permission this connection can currently grant across its scopes
  /// (most-permissive-wins, matching the server's evaluation).
  PermissionLevel get bestPermission => scopes.isEmpty
      ? PermissionLevel.none
      : scopes
          .map((s) => s.permissionLevel)
          .reduce((a, b) => a.rank >= b.rank ? a : b);

  /// True when this connection can currently grant any access.
  bool get grantsAccess =>
      isEnabled && scopes.any((s) => s.permissionLevel.rank > 0);

  factory Connection.fromJson(Map<String, dynamic> json) => Connection(
        connectionId: json['connectionId'] as String,
        targetCompany: CompanyRef.fromJson(
            (json['targetCompany'] as Map).cast<String, dynamic>()),
        targetTenant: TenantRef.fromJson(
            (json['targetTenant'] as Map).cast<String, dynamic>()),
        connectionType: ConnectionType.fromJson(json['connectionType'] as String?),
        isEnabled: json['isEnabled'] as bool? ?? false,
        permissionLevel: PermissionLevel.fromJson(json['permissionLevel'] as String?),
        scopes: ((json['scopes'] as List?) ?? const [])
            .map((e) =>
                ConnectionScope.fromJson((e as Map).cast<String, dynamic>()))
            .toList(growable: false),
        policyVersion: (json['policyVersion'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [
        connectionId,
        targetCompany,
        targetTenant,
        connectionType,
        isEnabled,
        permissionLevel,
        scopes,
        policyVersion,
      ];
}

/// The caller's effective scope — `GET /api/me/scope`.
class Scope extends Equatable {
  const Scope({
    required this.user,
    required this.activeTenant,
    required this.activeCompany,
    required this.activeLocation,
    required this.connections,
    required this.policyVersion,
  });

  final AuthUser user;
  final TenantRef activeTenant;
  final CompanyRef activeCompany;
  final LocationRef? activeLocation;
  final List<Connection> connections;
  final int policyVersion;

  /// Connections that can currently grant cross-tenant access.
  List<Connection> get accessibleConnections =>
      connections.where((c) => c.grantsAccess).toList(growable: false);

  bool get hasConnectedCompanies => connections.isNotEmpty;

  factory Scope.fromJson(Map<String, dynamic> json) => Scope(
        user: AuthUser.fromJson((json['user'] as Map).cast<String, dynamic>()),
        activeTenant: TenantRef.fromJson(
            (json['activeTenant'] as Map).cast<String, dynamic>()),
        activeCompany: CompanyRef.fromJson(
            (json['activeCompany'] as Map).cast<String, dynamic>()),
        activeLocation: json['activeLocation'] == null
            ? null
            : LocationRef.fromJson(
                (json['activeLocation'] as Map).cast<String, dynamic>()),
        connections: ((json['connections'] as List?) ?? const [])
            .map((e) => Connection.fromJson((e as Map).cast<String, dynamic>()))
            .toList(growable: false),
        policyVersion: (json['policyVersion'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [
        user,
        activeTenant,
        activeCompany,
        activeLocation,
        connections,
        policyVersion,
      ];
}
