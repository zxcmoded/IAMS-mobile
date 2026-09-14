import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/tenant/data/models/access.dart';
import 'package:iams_mobile/features/tenant/data/models/enums.dart';
import 'package:iams_mobile/features/tenant/data/models/scope.dart';

void main() {
  group('PermissionLevel', () {
    test('ranks Read < Write < Full and meets() compares correctly', () {
      expect(PermissionLevel.full.meets(PermissionLevel.write), isTrue);
      expect(PermissionLevel.read.meets(PermissionLevel.write), isFalse);
      expect(PermissionLevel.write.meets(PermissionLevel.write), isTrue);
      expect(PermissionLevel.none.meets(PermissionLevel.read), isFalse);
    });

    test('parses unknown values to a safe member', () {
      expect(PermissionLevel.fromJson('Nonsense'), PermissionLevel.unknown);
      expect(PermissionLevel.fromJson(null), PermissionLevel.unknown);
      expect(PermissionLevel.fromJson('Full'), PermissionLevel.full);
    });
  });

  group('AccessReason', () {
    test('maps every denial reason to an explanation', () {
      for (final r in AccessReason.values) {
        expect(r.explanation, isNotEmpty);
      }
    });
  });

  group('AccessDecision', () {
    test('allowed decision reports isAllowed', () {
      final d = AccessDecision.fromJson({
        'decision': 'Allowed',
        'effectivePermission': 'Full',
        'reason': 'ConnectionGranted',
        'connectionId': 'c1',
        'policyVersion': 12,
      });
      expect(d.isAllowed, isTrue);
      expect(d.reason, AccessReason.connectionGranted);
      expect(d.canDowngradeToReadOnly, isFalse);
    });

    test('insufficient permission with Read available offers read-only', () {
      final d = AccessDecision.fromJson({
        'decision': 'Denied',
        'effectivePermission': 'Read',
        'reason': 'InsufficientPermission',
        'connectionId': 'c1',
        'policyVersion': 12,
      });
      expect(d.isAllowed, isFalse);
      expect(d.canDowngradeToReadOnly, isTrue);
    });

    test('out-of-scope denial does not offer read-only', () {
      final d = AccessDecision.fromJson({
        'decision': 'Denied',
        'effectivePermission': 'None',
        'reason': 'OutOfScope',
      });
      expect(d.canDowngradeToReadOnly, isFalse);
    });
  });

  group('AccessRequest serialization', () {
    test('omits null hierarchy coordinates but always sends companyId', () {
      final req = AccessRequest(
        resource: const ResourceRef(companyId: 'co1', warehouseId: 'wh1'),
        requiredPermission: PermissionLevel.write,
      );
      final json = req.toJson();
      expect(json['requiredPermission'], 'Write');
      final resource = json['resource'] as Map<String, dynamic>;
      expect(resource['companyId'], 'co1');
      expect(resource['warehouseId'], 'wh1');
      expect(resource.containsKey('locationId'), isFalse);
      expect(resource.containsKey('binId'), isFalse);
    });
  });

  group('Scope', () {
    test('parses connections with multi-scope arrays and kind field', () {
      final scope = Scope.fromJson({
        'user': {'id': 'u1', 'username': 'alice', 'displayName': 'alice'},
        'activeTenant': {'id': 't1', 'name': 'Parent Co', 'kind': 'Parent'},
        'activeCompany': {'id': 'co1', 'name': 'Company A', 'tenantId': 't1'},
        'activeLocation': null,
        'connections': [
          {
            'connectionId': 'cn1',
            'targetCompany': {'id': 'co2', 'name': 'Company B', 'tenantId': 't2'},
            'targetTenant': {'id': 't2', 'name': 'Child Co', 'kind': 'Child'},
            'connectionType': 'ParentToChild',
            'isEnabled': true,
            'permissionLevel': 'Write',
            'scopes': [
              {'level': 'Warehouse', 'nodeId': 'wh1', 'permissionLevel': 'Full'},
              {'level': 'Location', 'nodeId': 'loc1', 'permissionLevel': 'Read'},
            ],
            'policyVersion': 12,
          },
          {
            'connectionId': 'cn2',
            'targetCompany': {'id': 'co3', 'name': 'Company C', 'tenantId': 't3'},
            'targetTenant': {'id': 't3', 'name': 'Child Co 2', 'kind': 'Child'},
            'connectionType': 'ParentToChild',
            'isEnabled': false,
            'permissionLevel': 'Read',
            'scopes': [
              {'level': 'Company', 'nodeId': 'co3', 'permissionLevel': 'Read'},
            ],
            'policyVersion': 9,
          },
        ],
        'policyVersion': 12,
      });

      expect(scope.activeLocation, isNull);
      expect(scope.activeTenant.kind, TenantType.parent);
      expect(scope.connections.length, 2);
      expect(scope.hasConnectedCompanies, isTrue);

      final cn1 = scope.connections.first;
      expect(cn1.scopes.length, 2);
      expect(cn1.scopes.first.level, ScopeLevel.warehouse);
      expect(cn1.scopes.first.permissionLevel, PermissionLevel.full);
      // most-permissive-wins across the connection's scopes.
      expect(cn1.bestPermission, PermissionLevel.full);
      expect(cn1.targetTenant.kind, TenantType.child);

      // Only the enabled connection grants access.
      expect(scope.accessibleConnections.length, 1);
      expect(scope.accessibleConnections.first.connectionId, 'cn1');
      expect(scope.connections[1].grantsAccess, isFalse);
    });

    test('a connection with an empty scopes array grants nothing', () {
      final scope = Scope.fromJson({
        'user': {'id': 'u1', 'username': 'a', 'displayName': 'a'},
        'activeTenant': {'id': 't1', 'name': 'T', 'kind': 'Parent'},
        'activeCompany': {'id': 'co1', 'name': 'C', 'tenantId': 't1'},
        'connections': [
          {
            'connectionId': 'cn1',
            'targetCompany': {'id': 'co2', 'name': 'B', 'tenantId': 't2'},
            'targetTenant': {'id': 't2', 'name': 'Child', 'kind': 'Child'},
            'connectionType': 'ParentToChild',
            'isEnabled': true,
            'permissionLevel': 'Write',
            'scopes': [],
            'policyVersion': 3,
          },
        ],
        'policyVersion': 3,
      });
      final cn = scope.connections.single;
      expect(cn.scopes, isEmpty);
      expect(cn.grantsAccess, isFalse);
      expect(cn.bestPermission, PermissionLevel.none);
    });

    test('empty connections means no connected company', () {
      final scope = Scope.fromJson({
        'user': {'id': 'u1', 'username': 'a', 'displayName': 'A'},
        'activeTenant': {'id': 't1', 'name': 'T', 'kind': 'Parent'},
        'activeCompany': {'id': 'co1', 'name': 'C', 'tenantId': 't1'},
        'connections': [],
        'policyVersion': 1,
      });
      expect(scope.hasConnectedCompanies, isFalse);
    });
  });
}
