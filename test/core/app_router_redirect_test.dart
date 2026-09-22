import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/router/app_router.dart';
import 'package:iams_mobile/core/router/app_routes.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_state.dart';

/// The offline-first change: an authenticated user must reach the Main Screen
/// (`/home`) immediately — the old blocking `/sync` gate is gone.
void main() {
  group('redirectForAuth', () {
    test('unknown → splash (until bootstrap resolves)', () {
      expect(redirectForAuth(AuthStatus.unknown, AppRoutes.home),
          AppRoutes.splash);
      expect(redirectForAuth(AuthStatus.unknown, AppRoutes.splash), isNull);
    });

    test('unauthenticated → activation', () {
      expect(redirectForAuth(AuthStatus.unauthenticated, AppRoutes.splash),
          AppRoutes.activation);
      expect(redirectForAuth(AuthStatus.unauthenticated, AppRoutes.activation),
          isNull);
    });

    test('sessionExpired → session-expired screen', () {
      expect(redirectForAuth(AuthStatus.sessionExpired, AppRoutes.home),
          AppRoutes.sessionExpired);
    });

    test('authenticated on splash → straight to /home (no /sync gate)', () {
      expect(redirectForAuth(AuthStatus.authenticated, AppRoutes.splash),
          AppRoutes.home);
    });

    test('authenticated on the activation/expired screens → /home', () {
      expect(redirectForAuth(AuthStatus.authenticated, AppRoutes.activation),
          AppRoutes.home);
      expect(
          redirectForAuth(AuthStatus.authenticated, AppRoutes.sessionExpired),
          AppRoutes.home);
    });

    test('authenticated already on an app screen stays put', () {
      expect(redirectForAuth(AuthStatus.authenticated, AppRoutes.home),
          isNull);
      expect(redirectForAuth(AuthStatus.authenticated, AppRoutes.inventory),
          isNull);
    });
  });
}
