import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/auth/data/auth_repository.dart';
import 'package:iams_mobile/features/auth/presentation/login/login_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repo;

  setUp(() => repo = MockAuthRepository());

  group('LoginCubit', () {
    blocTest<LoginCubit, LoginState>(
      'emits error with field errors when username/password are empty',
      build: () => LoginCubit(repo),
      act: (c) => c.submit(username: '  ', password: ''),
      expect: () => [
        isA<LoginState>()
            .having((s) => s.status, 'status', LoginStatus.error)
            .having((s) => s.fieldErrors.keys, 'fields',
                containsAll(['Username', 'Password'])),
      ],
      verify: (_) => verifyNever(() => repo.login(
            username: any(named: 'username'),
            password: any(named: 'password'),
          )),
    );

    blocTest<LoginCubit, LoginState>(
      'valid credentials → validating then challengeIssued with challenge',
      build: () {
        when(() => repo.login(
              username: 'alice',
              password: 's3cret',
            )).thenAnswer((_) async => buildChallenge());
        return LoginCubit(repo);
      },
      act: (c) => c.submit(username: 'alice', password: 's3cret'),
      expect: () => [
        isA<LoginState>().having((s) => s.status, 'status', LoginStatus.validating),
        isA<LoginState>()
            .having((s) => s.status, 'status', LoginStatus.challengeIssued)
            .having((s) => s.challenge, 'challenge', isNotNull),
      ],
    );

    blocTest<LoginCubit, LoginState>(
      'invalid_credentials → error with mapped message',
      build: () {
        when(() => repo.login(
              username: any(named: 'username'),
              password: any(named: 'password'),
            )).thenThrow(const ApiException(
          code: ApiErrorCode.invalidCredentials,
          message: 'Invalid username or password.',
        ));
        return LoginCubit(repo);
      },
      act: (c) => c.submit(username: 'alice', password: 'wrong'),
      expect: () => [
        isA<LoginState>().having((s) => s.status, 'status', LoginStatus.validating),
        isA<LoginState>()
            .having((s) => s.status, 'status', LoginStatus.error)
            .having((s) => s.errorCode, 'code', ApiErrorCode.invalidCredentials)
            .having((s) => s.errorMessage, 'message',
                'Incorrect username or password.'),
      ],
    );
  });
}
