import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/auth/data/auth_repository.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_controller.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_state.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repo;
  late FakeTokenStore store;

  setUp(() {
    repo = MockAuthRepository();
    store = FakeTokenStore();
  });

  AuthController build() =>
      AuthController(repository: repo, tokenStore: store);

  group('bootstrap', () {
    test('no persisted session → unauthenticated', () async {
      final c = build();
      await c.bootstrap();
      expect(c.state.status, AuthStatus.unauthenticated);
    });

    test('valid persisted session → authenticated', () async {
      store = FakeTokenStore(buildSession());
      final c = AuthController(repository: repo, tokenStore: store);
      await c.bootstrap();
      expect(c.state.status, AuthStatus.authenticated);
      expect(c.currentSession, isNotNull);
    });

    test('expired refresh token → unauthenticated and cleared', () async {
      store = FakeTokenStore(buildSession(
        refreshExpiry: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      ));
      final c = AuthController(repository: repo, tokenStore: store);
      await c.bootstrap();
      expect(c.state.status, AuthStatus.unauthenticated);
      expect(store.clears, greaterThan(0));
    });
  });

  group('onAuthenticated', () {
    test('persists the session and moves to authenticated', () async {
      final c = build();
      final session = buildSession();
      await c.onAuthenticated(session);
      expect(c.state.status, AuthStatus.authenticated);
      expect(store.writes, 1);
      expect(c.currentSession, session);
    });
  });

  group('refresh', () {
    test('success rotates and persists the new session', () async {
      final c = build();
      await c.onAuthenticated(buildSession(refreshToken: 'r1'));
      final rotated = buildSession(accessToken: 'a2', refreshToken: 'r2');
      when(() => repo.refresh('r1')).thenAnswer((_) async => rotated);

      final result = await c.refresh();

      expect(result.accessToken, 'a2');
      expect(c.currentSession!.refreshToken, 'r2');
      expect(c.state.status, AuthStatus.authenticated);
    });

    test('session_expired → sessionExpired state, cleared store, rethrows',
        () async {
      final c = build();
      await c.onAuthenticated(buildSession(refreshToken: 'r1'));
      when(() => repo.refresh('r1')).thenThrow(const ApiException(
        code: ApiErrorCode.sessionExpired,
        message: 'expired',
      ));

      await expectLater(c.refresh(), throwsA(isA<ApiException>()));
      expect(c.state.status, AuthStatus.sessionExpired);
      expect(store.clears, greaterThan(0));
    });

    test('coalesces concurrent refreshes into a single call', () async {
      final c = build();
      await c.onAuthenticated(buildSession(refreshToken: 'r1'));
      when(() => repo.refresh('r1')).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return buildSession(accessToken: 'a2', refreshToken: 'r2');
      });

      final results = await Future.wait([c.refresh(), c.refresh(), c.refresh()]);

      expect(results.every((s) => s.accessToken == 'a2'), isTrue);
      verify(() => repo.refresh('r1')).called(1);
    });
  });

  group('logout', () {
    test('clears the store and moves to unauthenticated', () async {
      final c = build();
      final session = buildSession();
      await c.onAuthenticated(session);
      when(() => repo.logout(
            accessTokenHeader: any(named: 'accessTokenHeader'),
            refreshToken: any(named: 'refreshToken'),
          )).thenAnswer((_) async {});

      await c.logout();

      expect(c.state.status, AuthStatus.unauthenticated);
      expect(c.currentSession, isNull);
      expect(store.clears, greaterThan(0));
    });

    test('local sign-out still completes if server logout throws', () async {
      final c = build();
      await c.onAuthenticated(buildSession());
      when(() => repo.logout(
            accessTokenHeader: any(named: 'accessTokenHeader'),
            refreshToken: any(named: 'refreshToken'),
          )).thenThrow(const ApiException(
        code: ApiErrorCode.network,
        message: 'offline',
      ));

      await c.logout();
      expect(c.state.status, AuthStatus.unauthenticated);
    });
  });

  group('acknowledgeSessionExpired', () {
    test('returns to unauthenticated', () async {
      final c = build();
      await c.onAuthenticated(buildSession(refreshToken: 'r1'));
      when(() => repo.refresh('r1')).thenThrow(const ApiException(
        code: ApiErrorCode.sessionExpired,
        message: 'expired',
      ));
      await expectLater(c.refresh(), throwsA(isA<ApiException>()));
      expect(c.state.status, AuthStatus.sessionExpired);

      c.acknowledgeSessionExpired();
      expect(c.state.status, AuthStatus.unauthenticated);
    });
  });
}
