// Enum types from the F15 contract. All are serialized as strings on the wire
// (e.g. "Read", "ParentToChild", "ConnectionGranted"). Each parser is
// tolerant of unknown values, falling back to a safe "unknown" member so a
// new server enum value never crashes the client.

enum PermissionLevel {
  none,
  read,
  write,
  full,
  unknown;

  static PermissionLevel fromJson(String? value) {
    switch (value) {
      case 'None':
        return PermissionLevel.none;
      case 'Read':
        return PermissionLevel.read;
      case 'Write':
        return PermissionLevel.write;
      case 'Full':
        return PermissionLevel.full;
      default:
        return PermissionLevel.unknown;
    }
  }

  /// Read < Write < Full ordering used for "meets requirement" comparisons.
  int get rank {
    switch (this) {
      case PermissionLevel.none:
      case PermissionLevel.unknown:
        return 0;
      case PermissionLevel.read:
        return 1;
      case PermissionLevel.write:
        return 2;
      case PermissionLevel.full:
        return 3;
    }
  }

  bool meets(PermissionLevel required) => rank >= required.rank;

  String get label {
    switch (this) {
      case PermissionLevel.none:
        return 'No access';
      case PermissionLevel.read:
        return 'Read';
      case PermissionLevel.write:
        return 'Write';
      case PermissionLevel.full:
        return 'Full access';
      case PermissionLevel.unknown:
        return 'Unknown';
    }
  }

  String toJson() {
    switch (this) {
      case PermissionLevel.none:
        return 'None';
      case PermissionLevel.read:
        return 'Read';
      case PermissionLevel.write:
        return 'Write';
      case PermissionLevel.full:
        return 'Full';
      case PermissionLevel.unknown:
        return 'None';
    }
  }
}

enum ConnectionType {
  parentToParent,
  parentToChild,
  childToParent,
  childToChild,
  unknown;

  static ConnectionType fromJson(String? value) {
    switch (value) {
      case 'ParentToParent':
        return ConnectionType.parentToParent;
      case 'ParentToChild':
        return ConnectionType.parentToChild;
      case 'ChildToParent':
        return ConnectionType.childToParent;
      case 'ChildToChild':
        return ConnectionType.childToChild;
      default:
        return ConnectionType.unknown;
    }
  }

  /// Compact badge form used in the connection list (P→C etc.).
  String get shortLabel {
    switch (this) {
      case ConnectionType.parentToParent:
        return 'P → P';
      case ConnectionType.parentToChild:
        return 'P → C';
      case ConnectionType.childToParent:
        return 'C → P';
      case ConnectionType.childToChild:
        return 'C → C';
      case ConnectionType.unknown:
        return '—';
    }
  }

  String get label {
    switch (this) {
      case ConnectionType.parentToParent:
        return 'Parent to Parent';
      case ConnectionType.parentToChild:
        return 'Parent to Child';
      case ConnectionType.childToParent:
        return 'Child to Parent';
      case ConnectionType.childToChild:
        return 'Child to Child';
      case ConnectionType.unknown:
        return 'Unknown connection';
    }
  }
}

enum ScopeLevel {
  company,
  location,
  warehouse,
  rack,
  bin,
  unknown;

  static ScopeLevel fromJson(String? value) {
    switch (value) {
      case 'Company':
        return ScopeLevel.company;
      case 'Location':
        return ScopeLevel.location;
      case 'Warehouse':
        return ScopeLevel.warehouse;
      case 'Rack':
        return ScopeLevel.rack;
      case 'Bin':
        return ScopeLevel.bin;
      default:
        return ScopeLevel.unknown;
    }
  }

  String get label {
    switch (this) {
      case ScopeLevel.company:
        return 'Whole company';
      case ScopeLevel.location:
        return 'Location';
      case ScopeLevel.warehouse:
        return 'Warehouse';
      case ScopeLevel.rack:
        return 'Rack';
      case ScopeLevel.bin:
        return 'Bin';
      case ScopeLevel.unknown:
        return 'Unknown scope';
    }
  }
}

enum TenantType {
  parent,
  child,
  unknown;

  static TenantType fromJson(String? value) {
    switch (value) {
      case 'Parent':
        return TenantType.parent;
      case 'Child':
        return TenantType.child;
      default:
        return TenantType.unknown;
    }
  }

  String get label {
    switch (this) {
      case TenantType.parent:
        return 'Parent';
      case TenantType.child:
        return 'Child';
      case TenantType.unknown:
        return 'Tenant';
    }
  }
}

enum AccessDecisionType {
  allowed,
  denied,
  unknown;

  static AccessDecisionType fromJson(String? value) {
    switch (value) {
      case 'Allowed':
        return AccessDecisionType.allowed;
      case 'Denied':
        return AccessDecisionType.denied;
      default:
        return AccessDecisionType.unknown;
    }
  }

  bool get isAllowed => this == AccessDecisionType.allowed;
}

enum AccessReason {
  sameTenant,
  connectionGranted,
  noConnection,
  connectionDisabled,
  outOfScope,
  insufficientPermission,
  unknown;

  static AccessReason fromJson(String? value) {
    switch (value) {
      case 'SameTenant':
        return AccessReason.sameTenant;
      case 'ConnectionGranted':
        return AccessReason.connectionGranted;
      case 'NoConnection':
        return AccessReason.noConnection;
      case 'ConnectionDisabled':
        return AccessReason.connectionDisabled;
      case 'OutOfScope':
        return AccessReason.outOfScope;
      case 'InsufficientPermission':
        return AccessReason.insufficientPermission;
      default:
        return AccessReason.unknown;
    }
  }

  /// Human-readable explanation shown on the Access Denied screen.
  String get explanation {
    switch (this) {
      case AccessReason.sameTenant:
        return 'This resource belongs to your own tenant.';
      case AccessReason.connectionGranted:
        return 'A connection grants you access to this resource.';
      case AccessReason.noConnection:
        return 'No connection is configured to this company.';
      case AccessReason.connectionDisabled:
        return 'The connection to this company is currently disabled.';
      case AccessReason.outOfScope:
        return 'This resource is outside the location scope your connection '
            'allows.';
      case AccessReason.insufficientPermission:
        return 'Your permission level is not high enough for this action.';
      case AccessReason.unknown:
        return 'Access could not be determined.';
    }
  }
}
