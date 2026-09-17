import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_controller.dart';
import 'package:iams_mobile/features/tenant/presentation/scope/company_selector_screen.dart';
import 'package:iams_mobile/features/tenant/presentation/scope/scope_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockScopeCubit extends MockCubit<ScopeState> implements ScopeCubit {}

class MockAuthController extends Mock implements AuthController {}

void main() {
  late MockScopeCubit scopeCubit;
  late MockAuthController authController;

  setUp(() {
    scopeCubit = MockScopeCubit();
    authController = MockAuthController();
    when(() => authController.logout()).thenAnswer((_) async {});
    when(() => authController.logoutAndForget()).thenAnswer((_) async {});

    if (sl.isRegistered<ScopeCubit>()) sl.unregister<ScopeCubit>();
    sl.registerFactory<ScopeCubit>(() => scopeCubit);
    if (sl.isRegistered<AuthController>()) sl.unregister<AuthController>();
    sl.registerLazySingleton<AuthController>(() => authController);

    // The appbar sign-out affordance renders regardless of scope-load state,
    // so an initial/loading state is enough for these tests.
    whenListen(scopeCubit, const Stream<ScopeState>.empty(),
        initialState: const ScopeState());
    when(scopeCubit.load).thenAnswer((_) async {});
  });

  tearDown(() => sl.reset());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CompanySelectorScreen()));
    await tester.pump();
  }

  testWidgets('tapping sign-out calls logout without any dialog',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('company_sign_out')));
    await tester.pump();

    verify(() => authController.logout()).called(1);
    verifyNever(() => authController.logoutAndForget());
    expect(find.byKey(const Key('forget_device_dialog')), findsNothing);
  });

  testWidgets(
      'long-pressing sign-out shows a confirmation dialog and does not '
      'forget the device yet', (tester) async {
    await pump(tester);

    await tester.longPress(find.byKey(const Key('company_sign_out')));
    // Body is left in ScopeStatus.initial for these tests, which renders a
    // CircularProgressIndicator (indefinite animation) — pumpAndSettle would
    // never terminate, so pump past the dialog's own transition instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('forget_device_dialog')), findsOneWidget);
    expect(find.text('Forget this device?'), findsOneWidget);
    verifyNever(() => authController.logoutAndForget());
  });

  testWidgets('cancelling the forget-device dialog does not forget the device',
      (tester) async {
    await pump(tester);

    await tester.longPress(find.byKey(const Key('company_sign_out')));
    // Body is left in ScopeStatus.initial for these tests, which renders a
    // CircularProgressIndicator (indefinite animation) — pumpAndSettle would
    // never terminate, so pump past the dialog's own transition instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('forget_device_cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('forget_device_dialog')), findsNothing);
    verifyNever(() => authController.logoutAndForget());
  });

  testWidgets('confirming the forget-device dialog forgets the device',
      (tester) async {
    await pump(tester);

    await tester.longPress(find.byKey(const Key('company_sign_out')));
    // Body is left in ScopeStatus.initial for these tests, which renders a
    // CircularProgressIndicator (indefinite animation) — pumpAndSettle would
    // never terminate, so pump past the dialog's own transition instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('forget_device_confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('forget_device_dialog')), findsNothing);
    verify(() => authController.logoutAndForget()).called(1);
  });
}
