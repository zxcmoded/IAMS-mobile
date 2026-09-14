import 'package:equatable/equatable.dart';

import 'enums.dart';

/// The resource coordinates for an access evaluation. `companyId` is required;
/// deeper ids are supplied as far as the resource resolves. A connection scoped
/// deeper than the coordinates supplied fails closed (Denied / OutOfScope).
class ResourceRef extends Equatable {
  const ResourceRef({
    required this.companyId,
    this.locationId,
    this.warehouseId,
    this.rackId,
    this.binId,
    this.resourceType,
    this.resourceId,
  });

  final String companyId;
  final String? locationId;
  final String? warehouseId;
  final String? rackId;
  final String? binId;
  final String? resourceType;
  final String? resourceId;

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        if (locationId != null) 'locationId': locationId,
        if (warehouseId != null) 'warehouseId': warehouseId,
        if (rackId != null) 'rackId': rackId,
        if (binId != null) 'binId': binId,
        if (resourceType != null) 'resourceType': resourceType,
        if (resourceId != null) 'resourceId': resourceId,
      };

  @override
  List<Object?> get props =>
      [companyId, locationId, warehouseId, rackId, binId, resourceType, resourceId];
}

/// Request body for `POST /api/access/evaluate`.
class AccessRequest extends Equatable {
  const AccessRequest({
    required this.resource,
    required this.requiredPermission,
  });

  final ResourceRef resource;
  final PermissionLevel requiredPermission;

  Map<String, dynamic> toJson() => {
        'resource': resource.toJson(),
        'requiredPermission': requiredPermission.toJson(),
      };

  @override
  List<Object?> get props => [resource, requiredPermission];
}

/// Response body for `POST /api/access/evaluate` (and each batch item's
/// `decision`).
class AccessDecision extends Equatable {
  const AccessDecision({
    required this.decision,
    required this.effectivePermission,
    required this.reason,
    required this.connectionId,
    required this.policyVersion,
  });

  final AccessDecisionType decision;
  final PermissionLevel effectivePermission;
  final AccessReason reason;
  final String? connectionId;
  final int? policyVersion;

  bool get isAllowed => decision.isAllowed;

  /// True when the action was denied only because the required permission was
  /// higher than what's available, yet at least read is possible — lets the UI
  /// offer a read-only affordance.
  bool get canDowngradeToReadOnly =>
      !isAllowed &&
      reason == AccessReason.insufficientPermission &&
      effectivePermission.rank >= PermissionLevel.read.rank;

  factory AccessDecision.fromJson(Map<String, dynamic> json) => AccessDecision(
        decision: AccessDecisionType.fromJson(json['decision'] as String?),
        effectivePermission:
            PermissionLevel.fromJson(json['effectivePermission'] as String?),
        reason: AccessReason.fromJson(json['reason'] as String?),
        connectionId: json['connectionId'] as String?,
        policyVersion: (json['policyVersion'] as num?)?.toInt(),
      );

  @override
  List<Object?> get props =>
      [decision, effectivePermission, reason, connectionId, policyVersion];
}
