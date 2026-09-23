import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/router/app_routes.dart';
import '../../../auth/data/models/auth_user.dart';
import '../../../auth/data/models/role.dart';
import '../../../auth/presentation/controller/auth_controller.dart';
import '../../../inventory/data/inventory_repository.dart';
import '../controller/selected_location_controller.dart';
import 'dashboard_cubit.dart';

/// Home — the offline-first Dashboard shown after activation + location select.
///
/// Renders entirely from local state (no network call required): the Company
/// from the local hierarchy cache, the Current Location resolved locally from
/// the persisted selection, and an Inventory Summary computed from local SQLite.
/// The user's identity + role come from the persisted auth session. Changing
/// the current location is a user-initiated action that reopens the (online)
/// location-select gate.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DashboardCubit>(
      create: (_) => sl<DashboardCubit>()..load(),
      child: const _HomeView(),
    );
  }
}

/// Confirms the destructive "forget this device" action before it runs.
/// Declining (or dismissing) the dialog is a no-op — [AuthController.
/// logoutAndForget] only fires once the user explicitly taps "Forget".
Future<void> _confirmForgetDevice(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('forget_device_dialog'),
      title: const Text('Forget this device?'),
      content: const Text(
        "You'll need to enter your activation key and pick a location again "
        'next time.',
      ),
      actions: [
        TextButton(
          key: const Key('forget_device_cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('forget_device_confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Forget'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    // Forgetting the device also forgets the current-location selection, so the
    // next user of this device gets the one-time location gate from scratch.
    await sl<AuthController>().logoutAndForget();
    await sl<SelectedLocationController>().clear();
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final user = sl<AuthController>().currentSession?.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            key: const Key('home_sign_out'),
            tooltip: 'Sign out (long-press to also forget this device)',
            icon: const Icon(Icons.logout),
            onPressed: () => sl<AuthController>().logout(),
            onLongPress: () => _confirmForgetDevice(context),
          ),
        ],
      ),
      body: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) {
          switch (state.status) {
            case DashboardStatus.loading:
              return const Center(child: CircularProgressIndicator());
            case DashboardStatus.error:
              return _ErrorState(
                message:
                    state.errorMessage ?? 'Could not load your dashboard.',
                onRetry: () => context.read<DashboardCubit>().refresh(),
              );
            case DashboardStatus.loaded:
              return _LoadedState(state: state, user: user);
          }
        },
      ),
    );
  }
}

class _LoadedState extends StatelessWidget {
  const _LoadedState({required this.state, required this.user});

  final DashboardState state;
  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => context.read<DashboardCubit>().refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Company', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _CompanyCard(companyName: state.companyName, user: user),
          const SizedBox(height: 24),
          Text('Current location',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _CurrentLocationCard(locationName: state.locationName),
          const SizedBox(height: 24),
          Text('Inventory summary',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _InventorySummary(summary: state.summary),
        ],
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.companyName, required this.user});

  final String? companyName;
  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final role = user?.role;
    return Card(
      key: const Key('dashboard_company_card'),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(Icons.business, color: scheme.onPrimaryContainer),
        ),
        title: Text(companyName ?? 'Your company'),
        subtitle: user == null ? null : Text(user!.displayName),
        trailing: (role != null && role != Role.unknown)
            ? _RoleBadge(role: role)
            : null,
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final Role role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: scheme.secondaryContainer,
      label: Text(
        role.label,
        style: TextStyle(color: scheme.onSecondaryContainer),
      ),
    );
  }
}

class _CurrentLocationCard extends StatelessWidget {
  const _CurrentLocationCard({required this.locationName});

  final String? locationName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('dashboard_location_card'),
      child: ListTile(
        leading: Icon(Icons.location_on_outlined, color: scheme.primary),
        title: Text(locationName ?? 'Selected location'),
        // Changing location reopens the (online) selection gate. Push over the
        // shell; the gate navigates back to the dashboard once a choice is made.
        trailing: TextButton(
          key: const Key('dashboard_change_location'),
          onPressed: () => context.push(AppRoutes.locationSelect),
          child: const Text('Change'),
        ),
      ),
    );
  }
}

class _InventorySummary extends StatelessWidget {
  const _InventorySummary({required this.summary});

  final InventorySummary summary;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight bounds the Row's height (to the taller tile) so the
    // stretched Expanded tiles render at equal height inside the ListView.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _SummaryTile(
              tileKey: const Key('dashboard_total_skus'),
              icon: Icons.inventory_2_outlined,
              label: 'Total SKUs',
              value: '${summary.totalSkus}',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SummaryTile(
              tileKey: const Key('dashboard_sync_status'),
              icon: summary.unsyncedCount == 0
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              label: 'Sync status',
              value: '${summary.syncedCount} synced',
              secondary: '${summary.unsyncedCount} offline',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.value,
    this.secondary,
  });

  final Key tileKey;
  final IconData icon;
  final String label;
  final String value;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: tileKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(height: 12),
            Text(value, style: theme.textTheme.headlineSmall),
            if (secondary != null)
              Text(
                secondary!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.outline),
              ),
            const SizedBox(height: 4),
            Text(
              label,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
