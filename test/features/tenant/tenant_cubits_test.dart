import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/auth/data/models/auth_user.dart';
import 'package:iams_mobile/features/tenant/data/models/access.dart';
import 'package:iams_mobile/features/tenant/data/models/enums.dart';
import 'package:iams_mobile/features/tenant/data/models/scope.dart';
import 'package:iams_mobile/features/tenant/data/tenant_repository.dart';
import 'package:iams_mobile/features/tenant/presentation/access/access_cubit.dart';
import 'package:iams_mobile/features/tenant/presentation/scope/scope_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockTenantRepository extends Mock implements TenantRepository {}

Scope _scope({bool withConnection = true}) => Scope(
      user: const AuthUser(id: 'u1', username: 'a', displayName: 'A'),
      activeTenant:
          const TenantRef(id: 't1', name: 'Parent', kind: TenantType.parent),
      activeCompany:
          const CompanyRef(id: 'co1', name: 'Company A', tenantId: 't1'),
      activeLocation: null,
      connections: withConnection
          ? [
              const Connection(
                connectionId: 'cn1',
                targetCompany:
                    CompanyRef(id: 'co2', name: 'Company B', tenantId: 't2'),
                targetTenant:
                    TenantRef(id: 't2', name: 'Child', kind: TenantType.child),
                connectionType: ConnectionType.parentToChild,
                isEnabled: true,
                permissionLevel: PermissionLevel.write,
                scopes: [
                  ConnectionScope(
                    level: ScopeLevel.warehouse,
                    nodeId: 'wh1',
                    permissionLevel: PermissionLevel.full,
                  ),
                ],
                policyVersion: 12,
              ),
            ]
          : const [],
      policyVersion: 12,
    );

void main() {
  late MockTenantRepository repo;

  setUp(() {
    repo = MockTenantRepository();
    registerFallbackValue(
      AccessRequest(
        resource: const ResourceRef(companyId: 'x'),
        requiredPermission: PermissionLevel.read,
      ),
    );
  });

  group('ScopeCubit', () {
    blocTest<ScopeCubit, ScopeState>(
      'load success → loading then loaded',
      build: () {
        when(repo.loadScope).thenAnswer((_) async => _scope());
        return ScopeCubit(repo);
      },
      act: (c) => c.load(),
      expect: () => [
        isA<ScopeState>().having((s) => s.status, 'status', ScopeStatus.loading),
        isA<ScopeState>()
            .having((s) => s.status, 'status', ScopeStatus.loaded)
            .having((s) => s.hasNoConnectedCompany, 'empty', isFalse),
      ],
    );

    blocTest<ScopeCubit, ScopeState>(
      'no connections → loaded empty state',
      build: () {
        when(repo.loadScope)
            .thenAnswer((_) async => _scope(withConnection: false));
        return ScopeCubit(repo);
      },
      act: (c) => c.load(),
      skip: 1,
      expect: () => [
        isA<ScopeState>()
            .having((s) => s.status, 'status', ScopeStatus.loaded)
            .having((s) => s.hasNoConnectedCompany, 'empty', isTrue),
      ],
    );

    blocTest<ScopeCubit, ScopeState>(
      'network failure → error carrying the code and a distinct offline message',
      build: () {
        when(repo.loadScope).thenThrow(const ApiException(
          code: ApiErrorCode.network,
          // The raw server/transport text is deliberately ignored in favour of
          // the explicit offline copy.
          message: 'SocketException: failed host lookup',
        ));
        return ScopeCubit(repo);
      },
      act: (c) => c.load(),
      skip: 1,
      expect: () => [
        isA<ScopeState>()
            .having((s) => s.status, 'status', ScopeStatus.error)
            .having((s) => s.errorCode, 'code', ApiErrorCode.network)
            .having((s) => s.errorMessage, 'message',
                "You're offline. Connect to the internet to view your companies."),
      ],
    );

    blocTest<ScopeCubit, ScopeState>(
      'non-network ApiException → error keeps the server-supplied message',
      build: () {
        when(repo.loadScope).thenThrow(const ApiException(
          code: ApiErrorCode.accessDenied,
          message: 'You do not have access to any company.',
          statusCode: 403,
        ));
        return ScopeCubit(repo);
      },
      act: (c) => c.load(),
      skip: 1,
      expect: () => [
        isA<ScopeState>()
            .having((s) => s.status, 'status', ScopeStatus.error)
            .having((s) => s.errorCode, 'code', ApiErrorCode.accessDenied)
            .having((s) => s.errorMessage, 'message',
                'You do not have access to any company.'),
      ],
    );

    blocTest<ScopeCubit, ScopeState>(
      'non-ApiException failure → error with a generic message, not stuck '
      'in loading',
      build: () {
        when(repo.loadScope).thenThrow(StateError('secure storage unavailable'));
        return ScopeCubit(repo);
      },
      act: (c) => c.load(),
      skip: 1,
      expect: () => [
        isA<ScopeState>()
            .having((s) => s.status, 'status', ScopeStatus.error)
            .having((s) => s.errorCode, 'code', ApiErrorCode.unknown)
            .having((s) => s.errorMessage, 'message', isNotNull)
            .having((s) => s.errorMessage, 'message',
                contains('Something went wrong')),
      ],
    );
  });

  group('AccessCubit', () {
    blocTest<AccessCubit, AccessState>(
      'allowed decision → evaluating then loaded',
      build: () {
        when(() => repo.evaluateAccess(any())).thenAnswer(
          (_) async => const AccessDecision(
            decision: AccessDecisionType.allowed,
            effectivePermission: PermissionLevel.full,
            reason: AccessReason.connectionGranted,
            connectionId: 'cn1',
            policyVersion: 12,
          ),
        );
        return AccessCubit(repo);
      },
      act: (c) => c.evaluate(AccessRequest(
        resource: const ResourceRef(companyId: 'co2', warehouseId: 'wh1'),
        requiredPermission: PermissionLevel.write,
      )),
      expect: () => [
        isA<AccessState>()
            .having((s) => s.status, 'status', AccessStatus.evaluating),
        isA<AccessState>()
            .having((s) => s.status, 'status', AccessStatus.loaded)
            .having((s) => s.decision!.isAllowed, 'allowed', isTrue),
      ],
    );

    blocTest<AccessCubit, AccessState>(
      'transport failure → error state',
      build: () {
        when(() => repo.evaluateAccess(any())).thenThrow(const ApiException(
          code: ApiErrorCode.network,
          message: 'offline',
        ));
        return AccessCubit(repo);
      },
      act: (c) => c.evaluate(AccessRequest(
        resource: const ResourceRef(companyId: 'co2'),
        requiredPermission: PermissionLevel.write,
      )),
      skip: 1,
      expect: () => [
        isA<AccessState>()
            .having((s) => s.status, 'status', AccessStatus.error),
      ],
    );

    blocTest<AccessCubit, AccessState>(
      'non-ApiException failure → error with a generic message, not stuck '
      'in evaluating',
      build: () {
        when(() => repo.evaluateAccess(any()))
            .thenThrow(StateError('secure storage unavailable'));
        return AccessCubit(repo);
      },
      act: (c) => c.evaluate(AccessRequest(
        resource: const ResourceRef(companyId: 'co2'),
        requiredPermission: PermissionLevel.write,
      )),
      skip: 1,
      expect: () => [
        isA<AccessState>()
            .having((s) => s.status, 'status', AccessStatus.error)
            .having((s) => s.errorCode, 'code', ApiErrorCode.unknown)
            .having((s) => s.errorMessage, 'message', isNotNull)
            .having((s) => s.errorMessage, 'message',
                contains('Something went wrong')),
      ],
    );
  });
}
