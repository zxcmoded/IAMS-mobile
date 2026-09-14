import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/features/auth/data/auth_repository.dart';
import 'package:iams_mobile/features/auth/data/models/auth_challenge.dart';
import 'package:iams_mobile/features/auth/presentation/login/login_cubit.dart';
import 'package:iams_mobile/features/auth/presentation/login/login_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repo;

  setUp(() {
    repo = MockAuthRepository();
    // LoginScreen resolves its cubit from the service locator.
    sl.registerFactory<LoginCubit>(() => LoginCubit(repo));
  });

  tearDown(() => sl.reset());

  testWidgets('renders the sign-in form', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets('empty submit shows inline field validation errors',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter your username.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    verifyNever(() => repo.login(
          username: any(named: 'username'),
          password: any(named: 'password'),
        ));
  });

  testWidgets('shows a busy indicator while validating credentials',
      (tester) async {
    // Keep the login pending so the screen stays in the validating state and
    // never navigates (navigation needs a router not present in this test).
    final completer = Completer<AuthChallenge>();
    when(() => repo.login(
          username: any(named: 'username'),
          password: any(named: 'password'),
        )).thenAnswer((_) => completer.future);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.enterText(find.byType(TextFormField).at(0), 'alice');
    await tester.enterText(find.byType(TextFormField).at(1), 's3cret');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump(); // start the async call

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Intentionally leave the login pending: completing it would fire the
    // success navigation, which needs a router this isolated test omits.
  });
}
