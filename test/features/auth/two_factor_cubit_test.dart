import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/auth/data/auth_repository.dart';
import 'package:iams_mobile/features/auth/presentation/two_factor/two_factor_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repo;

  setUp(() => repo = MockAuthRepository());

  TwoFactorCubit build() =>
      TwoFactorCubit(repo, buildChallenge(resendAvailableInSeconds: 0));

  group('TwoFactorCubit.verify', () {
    blocTest<TwoFactorCubit, TwoFactorState>(
      'valid code → verifying then verified carrying the session',
      build: () {
        when(() => repo.verifyTwoFactor(
              challengeToken: 'challenge-1',
              code: '123456',
            )).thenAnswer((_) async => buildSession());
        return build();
      },
      act: (c) => c.verify('123456'),
      expect: () => [
        isA<TwoFactorState>()
            .having((s) => s.status, 'status', TwoFactorStatus.verifying),
        isA<TwoFactorState>()
            .having((s) => s.status, 'status', TwoFactorStatus.verified)
            .having((s) => s.session, 'session', isNotNull),
      ],
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'two_factor_invalid → error (retryable)',
      build: () {
        when(() => repo.verifyTwoFactor(
              challengeToken: any(named: 'challengeToken'),
              code: any(named: 'code'),
            )).thenThrow(const ApiException(
          code: ApiErrorCode.twoFactorInvalid,
          message: 'wrong',
        ));
        return build();
      },
      act: (c) => c.verify('000000'),
      expect: () => [
        isA<TwoFactorState>()
            .having((s) => s.status, 'status', TwoFactorStatus.verifying),
        isA<TwoFactorState>()
            .having((s) => s.status, 'status', TwoFactorStatus.error)
            .having((s) => s.errorCode, 'code', ApiErrorCode.twoFactorInvalid),
      ],
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'no_active_company → terminal (expired) with a distinct message',
      build: () {
        when(() => repo.verifyTwoFactor(
              challengeToken: any(named: 'challengeToken'),
              code: any(named: 'code'),
            )).thenThrow(const ApiException(
          code: ApiErrorCode.noActiveCompany,
          statusCode: 403,
          message: 'No active company.',
        ));
        return build();
      },
      act: (c) => c.verify('123456'),
      expect: () => [
        isA<TwoFactorState>()
            .having((s) => s.status, 'status', TwoFactorStatus.verifying),
        isA<TwoFactorState>()
            .having((s) => s.status, 'status', TwoFactorStatus.expired)
            .having((s) => s.errorCode, 'code', ApiErrorCode.noActiveCompany)
            .having((s) => s.errorMessage, 'message',
                contains('linked to a company')),
      ],
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'device_already_registered → terminal (expired) with a distinct message',
      build: () {
        when(() => repo.verifyTwoFactor(
              challengeToken: any(named: 'challengeToken'),
              code: any(named: 'code'),
            )).thenThrow(const ApiException(
          code: ApiErrorCode.deviceAlreadyRegistered,
          statusCode: 403,
          message: 'mock message from backend',
        ));
        return build();
      },
      act: (c) => c.verify('123456'),
      expect: () => [
        isA<TwoFactorState>()
            .having((s) => s.status, 'status', TwoFactorStatus.verifying),
        isA<TwoFactorState>()
            .having((s) => s.status, 'status', TwoFactorStatus.expired)
            .having((s) => s.errorCode, 'code',
                ApiErrorCode.deviceAlreadyRegistered)
            .having(
              (s) => s.errorMessage,
              'message',
              'This account is already registered to another device. '
                  'Please contact your administrator to reset your device '
                  'registration.',
            ),
      ],
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'two_factor_expired → expired (restart login)',
      build: () {
        when(() => repo.verifyTwoFactor(
              challengeToken: any(named: 'challengeToken'),
              code: any(named: 'code'),
            )).thenThrow(const ApiException(
          code: ApiErrorCode.twoFactorExpired,
          message: 'expired',
        ));
        return build();
      },
      act: (c) => c.verify('123456'),
      expect: () => [
        isA<TwoFactorState>()
            .having((s) => s.status, 'status', TwoFactorStatus.verifying),
        isA<TwoFactorState>()
            .having((s) => s.status, 'status', TwoFactorStatus.expired),
      ],
    );
  });

  group('TwoFactorCubit.resend', () {
    blocTest<TwoFactorCubit, TwoFactorState>(
      'rotates the challenge token and restarts the cooldown',
      build: () {
        when(() => repo.resendTwoFactor('challenge-1')).thenAnswer(
          (_) async => buildChallenge(
            challengeToken: 'challenge-2',
            resendAvailableInSeconds: 30,
            devOtp: '654321',
          ),
        );
        return build();
      },
      act: (c) => c.resend(),
      wait: const Duration(milliseconds: 50),
      verify: (c) {
        expect(c.state.challengeToken, 'challenge-2');
        expect(c.state.devOtp, '654321');
        expect(c.state.resendCooldownSeconds, greaterThan(0));
      },
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'resend_too_soon → surfaces error but stays on screen',
      build: () {
        when(() => repo.resendTwoFactor(any())).thenThrow(const ApiException(
          code: ApiErrorCode.resendTooSoon,
          message: 'too soon',
        ));
        return build();
      },
      act: (c) => c.resend(),
      verify: (c) {
        expect(c.state.errorCode, ApiErrorCode.resendTooSoon);
        expect(c.state.isResending, isFalse);
      },
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'resend_limit_reached → terminal (expired) with a distinct message',
      build: () {
        when(() => repo.resendTwoFactor(any())).thenThrow(const ApiException(
          code: ApiErrorCode.resendLimitReached,
          statusCode: 429,
          message: 'limit',
        ));
        return build();
      },
      act: (c) => c.resend(),
      verify: (c) {
        expect(c.state.status, TwoFactorStatus.expired);
        expect(c.state.errorCode, ApiErrorCode.resendLimitReached);
        expect(c.state.errorMessage, contains('sign in again'));
        expect(c.state.isResending, isFalse);
      },
    );
  });

  group('cooldown vs. error (regression)', () {
    test('a per-second cooldown tick does not wipe a shown verify error',
        () async {
      when(() => repo.verifyTwoFactor(
            challengeToken: any(named: 'challengeToken'),
            code: any(named: 'code'),
          )).thenThrow(const ApiException(
        code: ApiErrorCode.twoFactorInvalid,
        message: 'wrong',
      ));
      // Start with an active cooldown so the periodic timer is ticking.
      final cubit =
          TwoFactorCubit(repo, buildChallenge(resendAvailableInSeconds: 3));
      addTearDown(cubit.close);

      await cubit.verify('000000');
      expect(cubit.state.status, TwoFactorStatus.error);
      expect(cubit.state.errorCode, ApiErrorCode.twoFactorInvalid);

      // Let at least one cooldown tick fire.
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      // The error must survive the tick (the bug wiped it within ~1s).
      expect(cubit.state.errorCode, ApiErrorCode.twoFactorInvalid);
      expect(cubit.state.errorMessage, isNotNull);
      expect(cubit.state.resendCooldownSeconds, lessThan(3));
    });
  });
}
