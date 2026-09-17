import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/activation/activation_screen.dart';
import '../../features/auth/presentation/controller/auth_controller.dart';
import '../../features/auth/presentation/controller/auth_state.dart';
import '../../features/auth/presentation/session_expired/session_expired_screen.dart';
import '../../features/inventory/presentation/adjust/adjustment_screen.dart';
import '../../features/inventory/presentation/count/stock_count_screen.dart';
import '../../features/inventory/presentation/detail/inventory_item_screen.dart';
import '../../features/inventory/presentation/list/inventory_list_screen.dart';
import '../../features/inventory/presentation/receive/receive_screen.dart';
import '../../features/inventory/presentation/shared/mutation_args.dart';
import '../../features/inventory/presentation/transfer/transfer_screen.dart';
import '../../features/tenant/presentation/access/access_denied_screen.dart';
import '../../features/tenant/presentation/access/cross_tenant_access_screen.dart';
import '../../features/masterdata/presentation/sync/hierarchy_sync_screen.dart';
import '../../features/scanning/presentation/manual_entry/manual_entry_screen.dart';
import '../../features/scanning/presentation/scanner/scanner_screen.dart';
import '../../features/tenant/presentation/scope/company_selector_screen.dart';
import '../../features/tenant/presentation/scope/connection_scope_screen.dart';
import 'app_routes.dart';
import 'go_router_refresh_stream.dart';

/// Builds the app router. Redirects are driven by [AuthController] state so the
/// user is always on a screen consistent with the session lifecycle:
/// unauthenticated → Activation Key entry, sessionExpired → Session Expired,
/// authenticated → the Sync screen (which then hands off to the Company
/// Selector once the offline store is ready).
GoRouter createRouter(AuthController auth) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: GoRouterRefreshStream(auth.stream),
    redirect: (context, state) {
      final status = auth.state.status;
      final loc = state.matchedLocation;

      if (status == AuthStatus.unknown) {
        return loc == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final onAuthFlow = loc == AppRoutes.activation;

      if (status == AuthStatus.sessionExpired) {
        return loc == AppRoutes.sessionExpired ? null : AppRoutes.sessionExpired;
      }

      if (status == AuthStatus.unauthenticated) {
        return onAuthFlow ? null : AppRoutes.activation;
      }

      // authenticated — land on the sync screen, which ensures the offline
      // store is ready before handing off to /companies itself.
      if (onAuthFlow ||
          loc == AppRoutes.splash ||
          loc == AppRoutes.sessionExpired) {
        return AppRoutes.sync;
      }
      return null;
    },
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
      GoRoute(
        path: AppRoutes.sync,
        builder: (_, _) => const HierarchySyncScreen(),
      ),
      GoRoute(
        path: AppRoutes.companies,
        builder: (_, _) => const CompanySelectorScreen(),
      ),
      GoRoute(
        path: AppRoutes.connectionScope,
        builder: (_, state) =>
            ConnectionScopeScreen(args: state.extra as ConnectionScopeArgs),
      ),
      GoRoute(
        path: AppRoutes.crossTenantAccess,
        builder: (_, state) => CrossTenantAccessScreen(
          args: state.extra as CrossTenantAccessArgs,
        ),
      ),
      GoRoute(
        path: AppRoutes.accessDenied,
        builder: (_, state) =>
            AccessDeniedScreen(args: state.extra as AccessDeniedArgs),
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

      // F4 — Inventory Operations
      GoRoute(
        path: AppRoutes.inventory,
        builder: (_, _) => const InventoryListScreen(),
      ),
      GoRoute(
        path: AppRoutes.inventoryItem,
        builder: (_, state) => InventoryItemScreen(
          itemId: state.uri.queryParameters['id'] ?? '',
        ),
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
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
