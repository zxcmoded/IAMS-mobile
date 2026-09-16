import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/auth/data/auth_repository.dart';
import 'package:iams_mobile/features/auth/data/models/auth_session.dart';
import 'package:iams_mobile/features/auth/presentation/activation/activation_cubit.dart';
import 'package:iams_mobile/features/auth/presentation/activation/activation_screen.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_controller.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_state.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repo;
  late AuthController authController;

  setUp(() {
    repo = MockAuthRepository();
    // ActivationScreen resolves its cubit from the service locator, and its
    // success listener hands the session to AuthController via sl<>().
    sl.registerFactory<ActivationCubit>(() => ActivationCubit(repo));
    authController =
        AuthController(repository: repo, tokenStore: FakeTokenStore());
    sl.registerLazySingleton<AuthController>(() => authController);
  });

  tearDown(() {
    sl.reset();
  });

  testWidgets('renders the activation key form', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ActivationScreen()));
    expect(find.text('Activate'), findsOneWidget);
    expect(find.byKey(const Key('activation_key_field')), findsOneWidget);
  });

  testWidgets('empty submit shows an inline field validation error',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ActivationScreen()));
    await tester.tap(find.widgetWithText(FilledButton, 'Activate'));
    await tester.pump();

    expect(find.text('Enter your activation key.'), findsOneWidget);
    verifyNever(() => repo.activate(any()));
  });

  testWidgets('shows a busy indicator while activating', (tester) async {
    final completer = Completer<AuthSession>();
    when(() => repo.activate(any())).thenAnswer((_) => completer.future);

    await tester.pumpWidget(const MaterialApp(home: ActivationScreen()));
    await tester.enterText(
        find.byKey(const Key('activation_key_field')), 'valid-key');
    await tester.tap(find.widgetWithText(FilledButton, 'Activate'));
    await tester.pump(); // start the async call

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Intentionally leave activation pending: completing it triggers the
    // success listener, which is covered separately below.
  });

  testWidgets(
      'terminal error (already bound) disables the field and offers Try again',
      (tester) async {
    when(() => repo.activate(any())).thenThrow(const ApiException(
      code: ApiErrorCode.activationKeyAlreadyBound,
      statusCode: 403,
      message: 'mock message from backend',
    ));

    await tester.pumpWidget(const MaterialApp(home: ActivationScreen()));
    await tester.enterText(
        find.byKey(const Key('activation_key_field')), 'someone-elses-key');
    await tester.tap(find.widgetWithText(FilledButton, 'Activate'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Activate'), findsNothing);

    final field = tester.widget<TextField>(
        find.byKey(const Key('activation_key_field')));
    expect(field.enabled, isFalse);
  });

  testWidgets(
      'non-ApiException failure shows a generic error and stops the spinner',
      (tester) async {
    when(() => repo.activate(any()))
        .thenThrow(StateError('secure storage unavailable'));

    await tester.pumpWidget(const MaterialApp(home: ActivationScreen()));
    await tester.enterText(
        find.byKey(const Key('activation_key_field')), 'valid-key');
    await tester.tap(find.widgetWithText(FilledButton, 'Activate'));
    await tester.pump();
    await tester.pump();

    // The spinner is gone and a generic, retryable error banner is shown.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('activation_error_message')), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'),
        findsOneWidget);
    // Retryable (not terminal): the Activate button remains, no Try again.
    expect(find.widgetWithText(FilledButton, 'Activate'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('successful activation hands the session to AuthController',
      (tester) async {
    when(() => repo.activate('valid-key'))
        .thenAnswer((_) async => buildSession());

    await tester.pumpWidget(const MaterialApp(home: ActivationScreen()));
    await tester.enterText(
        find.byKey(const Key('activation_key_field')), 'valid-key');
    await tester.tap(find.widgetWithText(FilledButton, 'Activate'));
    await tester.pump();
    await tester.pump();

    expect(authController.state.status, AuthStatus.authenticated);
  });
}
