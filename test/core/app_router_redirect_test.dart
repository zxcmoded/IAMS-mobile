import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/router/app_router.dart';
import 'package:iams_mobile/core/router/app_routes.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_state.dart';

/// The offline-first change: an authenticated user must reach the Main Screen
/// (`/companies`) immediately — the old blocking `/sync` gate is gone.
void main() {
  group('redirectForAuth', () {
    test('unknown → splash (until bootstrap resolves)', () {
      expect(redirectForAuth(AuthStatus.unknown, AppRoutes.companies),
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
      expect(redirectForAuth(AuthStatus.sessionExpired, AppRoutes.companies),
          AppRoutes.sessionExpired);
    });

    test('authenticated on splash → straight to /companies (no /sync gate)', () {
      expect(redirectForAuth(AuthStatus.authenticated, AppRoutes.splash),
          AppRoutes.companies);
    });

    test('authenticated on the activation/expired screens → /companies', () {
      expect(redirectForAuth(AuthStatus.authenticated, AppRoutes.activation),
          AppRoutes.companies);
      expect(
          redirectForAuth(AuthStatus.authenticated, AppRoutes.sessionExpired),
          AppRoutes.companies);
    });

    test('authenticated already on an app screen stays put', () {
      expect(redirectForAuth(AuthStatus.authenticated, AppRoutes.companies),
          isNull);
      expect(redirectForAuth(AuthStatus.authenticated, AppRoutes.inventory),
          isNull);
    });
  });
}
