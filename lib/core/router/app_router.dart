import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/audit/presentation/audit_screen.dart';
import '../../features/auth/presentation/activation/activation_screen.dart';
import '../../features/auth/presentation/controller/auth_controller.dart';
import '../../features/auth/presentation/controller/auth_state.dart';
import '../../features/auth/presentation/session_expired/session_expired_screen.dart';
import '../../features/inventory/presentation/adjust/adjustment_screen.dart';
import '../../features/inventory/presentation/count/stock_count_screen.dart';
import '../../features/inventory/presentation/create/create_inventory_screen.dart';
import '../../features/inventory/presentation/detail/inventory_item_screen.dart';
import '../../features/inventory/presentation/list/inventory_list_screen.dart';
import '../../features/inventory/presentation/records/inventory_records_screen.dart';
import '../../features/inventory/presentation/receive/receive_screen.dart';
import '../../features/inventory/presentation/shared/mutation_args.dart';
import '../../features/inventory/presentation/transfer/transfer_screen.dart';
import '../../features/access/presentation/access_denied/access_denied_screen.dart';
import '../../features/access/presentation/controller/selected_location_controller.dart';
import '../../features/access/presentation/home/home_screen.dart';
import '../../features/access/presentation/location_select/location_select_screen.dart';
import '../../features/scanning/presentation/manual_entry/manual_entry_screen.dart';
import '../../features/scanning/presentation/scanner/scanner_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../navigation/main_shell.dart';
import 'app_routes.dart';
import 'go_router_refresh_stream.dart';

/// Builds the app router. Redirects are driven by [AuthController] state so the
/// user is always on a screen consistent with the session lifecycle:
/// unauthenticated → Activation Key entry, sessionExpired → Session Expired,
/// authenticated → the Home screen (the Main Screen) **immediately**.
///
/// There is no longer a blocking `/sync` gate: offline data sync runs headlessly
/// in the background (see [SyncCoordinator]), never standing between auth and
/// the Main Screen in either connectivity state.
/// The pure redirect decision, factored out of [createRouter] so it is directly
/// unit-testable (no widget pump / DI). Returns the location to redirect to, or
/// `null` to stay put.
///
/// The rules, in order:
/// * An `authenticated` user with **no** persisted current-location selection
///   ([hasLocationSelection] `== false`) is sent to the one-time location-select
///   gate (`/location-select`) and held there until they choose.
/// * Once a location is selected, the original rule holds unchanged: an
///   `authenticated` user lands on the Home screen (`/home`, the Main Screen)
///   **immediately** — there is no blocking `/sync` gate; sync runs headlessly
///   in the background. `/location-select` remains reachable so the dashboard's
///   "Change" action can reopen it (the screen itself navigates back to Home).
String? redirectForAuth(
  AuthStatus status,
  bool hasLocationSelection,
  String location,
) {
  if (status == AuthStatus.unknown) {
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }

  final onAuthFlow = location == AppRoutes.activation;

  if (status == AuthStatus.sessionExpired) {
    return location == AppRoutes.sessionExpired
        ? null
        : AppRoutes.sessionExpired;
  }

  if (status == AuthStatus.unauthenticated) {
    return onAuthFlow ? null : AppRoutes.activation;
  }

  // authenticated with no location chosen yet — the one-time gate. Force the
  // location-select screen and hold there until a selection is persisted.
  if (!hasLocationSelection) {
    return location == AppRoutes.locationSelect
        ? null
        : AppRoutes.locationSelect;
  }

  // authenticated + a location is selected — land on Home immediately. Bounce
  // the pre-app screens to Home; `/location-select` is deliberately NOT bounced
  // so the "Change location" flow can reach it.
  if (onAuthFlow ||
      location == AppRoutes.splash ||
      location == AppRoutes.sessionExpired) {
    return AppRoutes.home;
  }
  return null;
}

GoRouter createRouter(AuthController auth, SelectedLocationController location) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    // Redirects react to both the auth lifecycle and the current-location
    // selection, so the router refreshes when either changes.
    refreshListenable: Listenable.merge([
      GoRouterRefreshStream(auth.stream),
      GoRouterRefreshStream(location.stream),
    ]),
    redirect: (context, state) => redirectForAuth(
      auth.state.status,
      location.state.hasSelection,
      state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => const _SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.activation,
        builder: (_, _) => const ActivationScreen(),
      ),
      GoRoute(
        path: AppRoutes.sessionExpired,
        builder: (_, _) => const SessionExpiredScreen(),
      ),
      // One-time "Select Current Location" gate, shown right after activation
      // (and re-openable via the dashboard's "Change" action). A top-level
      // route — outside the bottom-nav shell — so it covers the whole screen.
      GoRoute(
        path: AppRoutes.locationSelect,
        builder: (_, _) => const LocationSelectScreen(),
      ),
      // Persistent bottom-nav tabs (Home | Inventory | Audit | Settings).
      // `StatefulShellRoute.indexedStack` keeps each branch's own navigation
      // state alive (via IndexedStack) across tab switches. Sub-routes that
      // should push full-screen *over* the shell (inventory item detail,
      // receive/transfer/adjust/count, scanner, manual entry) are kept as
      // top-level sibling routes below, exactly as before — they are not
      // nested inside a branch, so they are not tabs themselves.
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (_, _) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.inventory,
                builder: (_, _) => const InventoryListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.audit,
                builder: (_, _) => const AuditScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.accessDenied,
        builder: (_, state) =>
            AccessDeniedScreen(args: state.extra as AccessDeniedArgs?),
      ),

      // F3 — Scanning
      GoRoute(
        path: AppRoutes.scanner,
        builder: (_, _) => const ScannerScreen(),
      ),
      GoRoute(
        path: AppRoutes.manualEntry,
        builder: (_, _) => const ManualEntryScreen(),
      ),

      // F4 — Inventory Operations (list itself is the Inventory tab, above)
      GoRoute(
        path: AppRoutes.inventoryItem,
        builder: (_, state) => InventoryItemScreen(
          itemId: state.uri.queryParameters['id'] ?? '',
        ),
      ),
      // Offline-first Create Inventory + saved offline records.
      GoRoute(
        path: AppRoutes.inventoryCreate,
        builder: (_, _) => const CreateInventoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.inventoryRecords,
        builder: (_, _) => const InventoryRecordsScreen(),
      ),
      GoRoute(
        path: AppRoutes.receive,
        builder: (_, state) =>
            ReceiveScreen(args: state.extra as MutationArgs),
      ),
      GoRoute(
        path: AppRoutes.transfer,
        builder: (_, state) =>
            TransferScreen(args: state.extra as MutationArgs),
      ),
      GoRoute(
        path: AppRoutes.adjust,
        builder: (_, state) =>
            AdjustmentScreen(args: state.extra as MutationArgs),
      ),
      GoRoute(
        path: AppRoutes.stockCount,
        builder: (_, state) =>
            StockCountScreen(args: state.extra as MutationArgs),
      ),
    ],
  );
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/giso_logo.png',
              width: 160,
              semanticLabel: 'GISO logo',
            ),
            const SizedBox(height: 32),
            CircularProgressIndicator(color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
