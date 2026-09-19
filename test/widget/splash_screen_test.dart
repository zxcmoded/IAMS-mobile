import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/router/app_router.dart';
import 'package:iams_mobile/features/auth/data/auth_repository.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_controller.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  // The splash screen (`_SplashScreen`) is a private widget in
  // `app_router.dart`, so it's exercised here through the real router at its
  // initial location. `AuthController` starts life in `AuthStatus.unknown`
  // (see `AuthState.unknown()`) until `bootstrap()` resolves it — we never
  // call `bootstrap()`, so the router's redirect keeps us on `/`.
  testWidgets('splash screen shows the GISO logo and a progress indicator',
      (tester) async {
    final auth = AuthController(
      repository: MockAuthRepository(),
      tokenStore: FakeTokenStore(),
      rememberedKeyStore: FakeRememberedActivationKeyStore(),
    );
    addTearDown(auth.close);

    await tester.pumpWidget(MaterialApp.router(routerConfig: createRouter(auth)));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/giso_logo.png',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
