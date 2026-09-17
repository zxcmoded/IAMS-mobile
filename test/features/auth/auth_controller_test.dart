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
  late FakeRememberedActivationKeyStore rememberedStore;

  setUp(() {
    repo = MockAuthRepository();
    store = FakeTokenStore();
    rememberedStore = FakeRememberedActivationKeyStore();
  });

  AuthController build() => AuthController(
        repository: repo,
        tokenStore: store,
        rememberedKeyStore: rememberedStore,
      );

  group('bootstrap', () {
    test('no persisted session → unauthenticated', () async {
      final c = build();
      await c.bootstrap();
      expect(c.state.status, AuthStatus.unauthenticated);
    });

    test('persisted session → authenticated (reused as-is, no refresh)',
        () async {
      store = FakeTokenStore(buildSession());
      final c = AuthController(
        repository: repo,
        tokenStore: store,
        rememberedKeyStore: rememberedStore,
      );
      await c.bootstrap();
      expect(c.state.status, AuthStatus.authenticated);
      expect(c.currentSession, isNotNull);
      // The token is reused verbatim — nothing is cleared or re-fetched.
      expect(store.clears, 0);
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

  group('invalidateSession (401 on an authenticated request)', () {
    test('clears the store and moves to sessionExpired', () async {
      final c = build();
      await c.onAuthenticated(buildSession());

      c.invalidateSession();

      expect(c.state.status, AuthStatus.sessionExpired);
      expect(store.clears, greaterThan(0));
      // The now-unusable session reference is dropped from state.
      expect(c.currentSession, isNull);
    });

    test('is a no-op when already unauthenticated', () async {
      final c = build();
      await c.bootstrap(); // unauthenticated
      c.invalidateSession();
      expect(c.state.status, AuthStatus.unauthenticated);
      expect(store.clears, 0);
    });

    test('is a no-op when already sessionExpired (idempotent)', () async {
      final c = build();
      await c.onAuthenticated(buildSession());
      c.invalidateSession();
      final clearsAfterFirst = store.clears;
      c.invalidateSession();
      expect(c.state.status, AuthStatus.sessionExpired);
      expect(store.clears, clearsAfterFirst);
    });
  });

  group('logout', () {
    test('calls server logout, clears store, moves to unauthenticated',
        () async {
      final c = build();
      final session = buildSession();
      await c.onAuthenticated(session);
      when(() => repo.logout(
            accessTokenHeader: any(named: 'accessTokenHeader'),
          )).thenAnswer((_) async {});

      await c.logout();

      verify(() => repo.logout(
            accessTokenHeader: session.authorizationHeader,
          )).called(1);
      expect(c.state.status, AuthStatus.unauthenticated);
      expect(c.currentSession, isNull);
      expect(store.clears, greaterThan(0));
    });

    test('always clears local state even if server logout throws', () async {
      final c = build();
      await c.onAuthenticated(buildSession());
      when(() => repo.logout(
            accessTokenHeader: any(named: 'accessTokenHeader'),
          )).thenThrow(const ApiException(
        code: ApiErrorCode.network,
        message: 'offline',
      ));

      await c.logout();

      expect(c.state.status, AuthStatus.unauthenticated);
      expect(c.currentSession, isNull);
      expect(store.clears, greaterThan(0));
    });

    test('preserves the remembered activation key (one-tap resume survives)',
        () async {
      rememberedStore = FakeRememberedActivationKeyStore('remembered-key');
      final c = build();
      await c.onAuthenticated(buildSession());
      when(() => repo.logout(
            accessTokenHeader: any(named: 'accessTokenHeader'),
          )).thenAnswer((_) async {});

      await c.logout();

      // Session gone, but the remembered key is untouched.
      expect(store.clears, greaterThan(0));
      expect(rememberedStore.clears, 0);
      expect(rememberedStore.value, 'remembered-key');
    });
  });

  group('logoutAndForget', () {
    test('signs out AND clears the remembered activation key', () async {
      rememberedStore = FakeRememberedActivationKeyStore('remembered-key');
      final c = build();
      await c.onAuthenticated(buildSession());
      when(() => repo.logout(
            accessTokenHeader: any(named: 'accessTokenHeader'),
          )).thenAnswer((_) async {});

      await c.logoutAndForget();

      expect(c.state.status, AuthStatus.unauthenticated);
      expect(c.currentSession, isNull);
      expect(store.clears, greaterThan(0));
      expect(rememberedStore.clears, greaterThan(0));
      expect(rememberedStore.value, isNull);
    });
  });

  group('acknowledgeSessionExpired', () {
    test('returns to unauthenticated', () async {
      final c = build();
      await c.onAuthenticated(buildSession());
      c.invalidateSession();
      expect(c.state.status, AuthStatus.sessionExpired);

      c.acknowledgeSessionExpired();
      expect(c.state.status, AuthStatus.unauthenticated);
    });
  });
}
