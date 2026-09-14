import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/auth/data/models/auth_user.dart';
import 'package:iams_mobile/features/tenant/data/models/access.dart';
import 'package:iams_mobile/features/tenant/data/models/enums.dart';
import 'package:iams_mobile/features/tenant/data/models/scope.dart';
import 'package:iams_mobile/features/tenant/presentation/access/access_denied_screen.dart';

Scope _scope() => const Scope(
      user: AuthUser(id: 'u1', username: 'a', displayName: 'A'),
      activeTenant: TenantRef(id: 't1', name: 'Parent', kind: TenantType.parent),
      activeCompany: CompanyRef(id: 'co1', name: 'Company A', tenantId: 't1'),
      activeLocation: null,
      connections: [],
      policyVersion: 12,
    );

AccessDecision _decision(AccessReason reason) => AccessDecision(
      decision: AccessDecisionType.denied,
      effectivePermission: PermissionLevel.read,
      reason: reason,
      connectionId: 'cn1',
      policyVersion: 12,
    );

Future<void> _pump(WidgetTester tester, AccessReason reason) async {
  await tester.pumpWidget(MaterialApp(
    home: AccessDeniedScreen(
      args: AccessDeniedArgs(scope: _scope(), decision: _decision(reason)),
    ),
  ));
}

void main() {
  testWidgets('disabled-connection maps to the disabled title + reason',
      (tester) async {
    await _pump(tester, AccessReason.connectionDisabled);
    expect(find.text('Connection disabled'), findsOneWidget);
    expect(
      find.text('The connection to this company is currently disabled.'),
      findsOneWidget,
    );
  });

  testWidgets('outside-location-scope maps to the scope title', (tester) async {
    await _pump(tester, AccessReason.outOfScope);
    expect(find.text('Outside your location scope'), findsOneWidget);
  });

  testWidgets('insufficient-permission maps to the permission title',
      (tester) async {
    await _pump(tester, AccessReason.insufficientPermission);
    expect(find.text('Insufficient permission'), findsOneWidget);
    expect(find.text('Read'), findsWidgets); // effective permission row
  });

  testWidgets('offers return and switch-company actions', (tester) async {
    await _pump(tester, AccessReason.insufficientPermission);
    expect(find.widgetWithText(FilledButton, 'Return'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Switch company'),
      findsOneWidget,
    );
  });
}
