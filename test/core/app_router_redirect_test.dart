import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/router/app_router.dart';
import 'package:iams_mobile/core/router/app_routes.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_state.dart';

/// The offline-first rule: an authenticated user reaches the Main Screen
/// (`/home`) immediately — the old blocking `/sync` gate is gone — EXCEPT for
/// the one-time location-select gate, which holds a freshly-authenticated user
/// on `/location-select` until they pick a current location. Once a location is
/// selected, the straight-to-Home rule is restored.
void main() {
  group('redirectForAuth', () {
    // A user who has already picked a location — the steady state after the
    // one-time gate is satisfied.
    const selected = true;
    const noSelection = false;

    test('unknown → splash (until bootstrap resolves)', () {
      expect(redirectForAuth(AuthStatus.unknown, selected, AppRoutes.home),
          AppRoutes.splash);
      expect(redirectForAuth(AuthStatus.unknown, selected, AppRoutes.splash),
          isNull);
    });

    test('unauthenticated → activation', () {
      expect(
          redirectForAuth(
              AuthStatus.unauthenticated, noSelection, AppRoutes.splash),
          AppRoutes.activation);
      expect(
          redirectForAuth(
              AuthStatus.unauthenticated, noSelection, AppRoutes.activation),
          isNull);
    });

    test('sessionExpired → session-expired screen', () {
      expect(
          redirectForAuth(
              AuthStatus.sessionExpired, selected, AppRoutes.home),
          AppRoutes.sessionExpired);
    });

    group('one-time location gate (authenticated, no selection)', () {
      test('anywhere → forced to /location-select', () {
        expect(
            redirectForAuth(
                AuthStatus.authenticated, noSelection, AppRoutes.home),
            AppRoutes.locationSelect);
        expect(
            redirectForAuth(
                AuthStatus.authenticated, noSelection, AppRoutes.splash),
            AppRoutes.locationSelect);
        expect(
            redirectForAuth(
                AuthStatus.authenticated, noSelection, AppRoutes.inventory),
            AppRoutes.locationSelect);
      });

      test('already on /location-select stays put', () {
        expect(
            redirectForAuth(AuthStatus.authenticated, noSelection,
                AppRoutes.locationSelect),
            isNull);
      });
    });

    group('after a location is selected', () {
      test('authenticated on splash → straight to /home (no /sync gate)', () {
        expect(
            redirectForAuth(
                AuthStatus.authenticated, selected, AppRoutes.splash),
            AppRoutes.home);
      });

      test('authenticated on the activation/expired screens → /home', () {
        expect(
            redirectForAuth(
                AuthStatus.authenticated, selected, AppRoutes.activation),
            AppRoutes.home);
        expect(
            redirectForAuth(
                AuthStatus.authenticated, selected, AppRoutes.sessionExpired),
            AppRoutes.home);
      });

      test('authenticated already on an app screen stays put', () {
        expect(
            redirectForAuth(
                AuthStatus.authenticated, selected, AppRoutes.home),
            isNull);
        expect(
            redirectForAuth(
                AuthStatus.authenticated, selected, AppRoutes.inventory),
            isNull);
      });

      test(
          '/location-select is reachable so the "Change" action is not bounced',
          () {
        expect(
            redirectForAuth(AuthStatus.authenticated, selected,
                AppRoutes.locationSelect),
            isNull);
      });
    });
  });
}
