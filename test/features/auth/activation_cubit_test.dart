import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/auth/data/auth_repository.dart';
import 'package:iams_mobile/features/auth/presentation/activation/activation_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repo;
  late FakeRememberedActivationKeyStore remembered;

  setUp(() {
    repo = MockAuthRepository();
    remembered = FakeRememberedActivationKeyStore();
  });

  group('ActivationCubit.submit', () {
    blocTest<ActivationCubit, ActivationState>(
      'emits error with a field error when the key is empty',
      build: () => ActivationCubit(repo, remembered),
      act: (c) => c.submit(activationKey: '   '),
      expect: () => [
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.error)
            .having((s) => s.fieldErrors.keys, 'fields',
                contains('ActivationKey')),
      ],
      verify: (_) => verifyNever(() => repo.activate(any())),
    );

    blocTest<ActivationCubit, ActivationState>(
      'valid key → activating then activated carrying the session',
      build: () {
        when(() => repo.activate('valid-key'))
            .thenAnswer((_) async => buildSession());
        return ActivationCubit(repo, remembered);
      },
      act: (c) => c.submit(activationKey: 'valid-key'),
      expect: () => [
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.activating),
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.activated)
            .having((s) => s.session, 'session', isNotNull),
      ],
    );

    blocTest<ActivationCubit, ActivationState>(
      'trims surrounding whitespace before calling the repository',
      build: () {
        when(() => repo.activate('valid-key'))
            .thenAnswer((_) async => buildSession());
        return ActivationCubit(repo, remembered);
      },
      act: (c) => c.submit(activationKey: '  valid-key  '),
      verify: (_) => verify(() => repo.activate('valid-key')).called(1),
    );

    blocTest<ActivationCubit, ActivationState>(
      'activation_key_invalid → error (retryable) with mapped message',
      build: () {
        when(() => repo.activate(any())).thenThrow(const ApiException(
          code: ApiErrorCode.activationKeyInvalid,
          message: 'mock message from backend',
        ));
        return ActivationCubit(repo, remembered);
      },
      act: (c) => c.submit(activationKey: 'bad-key'),
      expect: () => [
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.activating),
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.error)
            .having((s) => s.errorCode, 'code', ApiErrorCode.activationKeyInvalid)
            .having((s) => s.errorMessage, 'message',
                contains('isn\'t valid')),
      ],
    );

    blocTest<ActivationCubit, ActivationState>(
      'activation_key_already_bound → terminal with a distinct message',
      build: () {
        when(() => repo.activate(any())).thenThrow(const ApiException(
          code: ApiErrorCode.activationKeyAlreadyBound,
          statusCode: 403,
          message: 'mock message from backend',
        ));
        return ActivationCubit(repo, remembered);
      },
      act: (c) => c.submit(activationKey: 'someone-elses-key'),
      expect: () => [
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.activating),
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.terminal)
            .having((s) => s.errorCode, 'code',
                ApiErrorCode.activationKeyAlreadyBound)
            .having(
              (s) => s.errorMessage,
              'message',
              contains('registered to another device'),
            ),
      ],
    );

    blocTest<ActivationCubit, ActivationState>(
      'network error → error (retryable), falls through to e.message',
      build: () {
        when(() => repo.activate(any())).thenThrow(const ApiException(
          code: ApiErrorCode.network,
          message: 'Network unavailable. Check your connection and retry.',
        ));
        return ActivationCubit(repo, remembered);
      },
      act: (c) => c.submit(activationKey: 'valid-key'),
      expect: () => [
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.activating),
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.error)
            .having((s) => s.errorCode, 'code', ApiErrorCode.network)
            .having((s) => s.errorMessage, 'message',
                'Network unavailable. Check your connection and retry.'),
      ],
    );
    blocTest<ActivationCubit, ActivationState>(
      'non-ApiException failure → error with a generic message, not stuck '
      'in activating',
      build: () {
        when(() => repo.activate(any()))
            .thenThrow(StateError('secure storage unavailable'));
        return ActivationCubit(repo, remembered);
      },
      act: (c) => c.submit(activationKey: 'valid-key'),
      expect: () => [
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.activating),
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.error)
            .having((s) => s.errorMessage, 'message', isNotNull)
            .having((s) => s.errorMessage, 'message',
                contains('Something went wrong'))
            .having((s) => s.errorCode, 'code', ApiErrorCode.unknown),
      ],
    );
  });

  group('ActivationCubit.reset', () {
    blocTest<ActivationCubit, ActivationState>(
      'returns to idle from a terminal state',
      build: () {
        when(() => repo.activate(any())).thenThrow(const ApiException(
          code: ApiErrorCode.activationKeyAlreadyBound,
          statusCode: 403,
          message: 'bound',
        ));
        return ActivationCubit(repo, remembered);
      },
      act: (c) async {
        await c.submit(activationKey: 'someone-elses-key');
        c.reset();
      },
      skip: 2,
      expect: () => [
        const ActivationState(),
      ],
    );
  });

  group('remembers the key on success', () {
    blocTest<ActivationCubit, ActivationState>(
      'writes the raw typed key to the remembered-key store on activation',
      build: () {
        when(() => repo.activate('valid-key'))
            .thenAnswer((_) async => buildSession());
        return ActivationCubit(repo, remembered);
      },
      act: (c) => c.submit(activationKey: '  valid-key  '),
      verify: (_) {
        // The trimmed key the user actually typed is remembered (not derived
        // from the response, which never echoes the key).
        expect(remembered.value, 'valid-key');
        expect(remembered.writes, 1);
      },
    );

    blocTest<ActivationCubit, ActivationState>(
      'does not remember a key when activation fails',
      build: () {
        when(() => repo.activate(any())).thenThrow(const ApiException(
          code: ApiErrorCode.activationKeyInvalid,
          message: 'bad',
        ));
        return ActivationCubit(repo, remembered);
      },
      act: (c) => c.submit(activationKey: 'bad-key'),
      verify: (_) => expect(remembered.value, isNull),
    );
  });

  group('loadRemembered', () {
    blocTest<ActivationCubit, ActivationState>(
      'no remembered key → stays on the blank entry form (no emit)',
      build: () => ActivationCubit(repo, remembered),
      act: (c) => c.loadRemembered(),
      expect: () => const <ActivationState>[],
    );

    blocTest<ActivationCubit, ActivationState>(
      'remembered key present → enters the resume state',
      build: () {
        remembered = FakeRememberedActivationKeyStore('remembered-key');
        return ActivationCubit(repo, remembered);
      },
      act: (c) => c.loadRemembered(),
      expect: () => [
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.resume)
            .having((s) => s.isResume, 'isResume', isTrue),
      ],
    );
  });

  group('resume', () {
    blocTest<ActivationCubit, ActivationState>(
      'one-tap resume re-activates with the remembered key',
      build: () {
        remembered = FakeRememberedActivationKeyStore('remembered-key');
        when(() => repo.activate('remembered-key'))
            .thenAnswer((_) async => buildSession());
        return ActivationCubit(repo, remembered);
      },
      act: (c) async {
        await c.loadRemembered();
        await c.resume();
      },
      expect: () => [
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.resume),
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.activating),
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.activated)
            .having((s) => s.session, 'session', isNotNull),
      ],
      verify: (_) => verify(() => repo.activate('remembered-key')).called(1),
    );

    blocTest<ActivationCubit, ActivationState>(
      'failed resume forgets the key and falls back to manual entry with the '
      'mapped error',
      build: () {
        remembered = FakeRememberedActivationKeyStore('stale-key');
        when(() => repo.activate('stale-key')).thenThrow(const ApiException(
          code: ApiErrorCode.activationKeyInvalid,
          statusCode: 401,
          message: 'mock message from backend',
        ));
        return ActivationCubit(repo, remembered);
      },
      act: (c) async {
        await c.loadRemembered();
        await c.resume();
      },
      expect: () => [
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.resume),
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.activating),
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.error)
            .having(
                (s) => s.errorCode, 'code', ApiErrorCode.activationKeyInvalid)
            .having((s) => s.errorMessage, 'message', contains('isn\'t valid')),
      ],
      verify: (_) {
        // The stale key is forgotten so the user isn't stuck on a broken
        // one-tap resume.
        expect(remembered.value, isNull);
        expect(remembered.clears, greaterThan(0));
      },
    );

  });

  group('useDifferentKey', () {
    blocTest<ActivationCubit, ActivationState>(
      'forgets the remembered key and returns to the blank entry form',
      build: () {
        remembered = FakeRememberedActivationKeyStore('remembered-key');
        return ActivationCubit(repo, remembered);
      },
      act: (c) async {
        await c.loadRemembered();
        await c.useDifferentKey();
      },
      expect: () => [
        isA<ActivationState>()
            .having((s) => s.status, 'status', ActivationStatus.resume),
        const ActivationState(),
      ],
      verify: (_) {
        expect(remembered.value, isNull);
        expect(remembered.clears, greaterThan(0));
      },
    );
  });
}
