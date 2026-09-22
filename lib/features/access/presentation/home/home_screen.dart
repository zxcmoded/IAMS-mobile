import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/router/app_routes.dart';
import '../../../auth/data/models/role.dart';
import '../../../auth/presentation/controller/auth_controller.dart';
import '../../data/models/scope.dart';
import 'scope_cubit.dart';

/// Home — the Main Screen after activation. Shows the caller's Company, role,
/// and the Locations they may act within (`/me/scope`), plus entry points into
/// Scanning and Inventory. There is no company/location switching: a user acts
/// within their Company + full assigned-Location set at all times.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ScopeCubit>(
      create: (_) => sl<ScopeCubit>()..load(),
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
        "You'll need to enter your activation key again next time.",
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
    await sl<AuthController>().logoutAndForget();
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: 'Scan',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => context.push(AppRoutes.scanner),
          ),
          IconButton(
            tooltip: 'Inventory',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => context.push(AppRoutes.inventory),
          ),
          // Tap: sign out but keep this device remembered (one-tap resume on
          // the Activation screen). Long-press: also forget the remembered key,
          // for a shared/kiosk device being handed off. Forgetting is
          // destructive (it forces a full manual key re-entry later), so it
          // always goes through a confirmation dialog before it runs.
          //
          // Uses IconButton's own onLongPress (rather than wrapping it in a
          // separate GestureDetector) because IconButton also owns the
          // tooltip's internal LongPressGestureRecognizer — a sibling
          // GestureDetector competes with that recognizer in the same gesture
          // arena and can lose to it, silently swallowing the long press.
          IconButton(
            key: const Key('home_sign_out'),
            tooltip: 'Sign out (long-press to also forget this device)',
            icon: const Icon(Icons.logout),
            onPressed: () => sl<AuthController>().logout(),
            onLongPress: () => _confirmForgetDevice(context),
          ),
        ],
      ),
      body: BlocBuilder<ScopeCubit, ScopeState>(
        builder: (context, state) {
          switch (state.status) {
            case ScopeStatus.initial:
            case ScopeStatus.loading:
              return const Center(child: CircularProgressIndicator());
            case ScopeStatus.error:
              return _ErrorState(
                message: state.errorMessage ?? 'Could not load your access.',
                onRetry: () => context.read<ScopeCubit>().refresh(),
              );
            case ScopeStatus.loaded:
              return _LoadedState(scope: state.scope!);
          }
        },
      ),
    );
  }
}

class _LoadedState extends StatelessWidget {
  const _LoadedState({required this.scope});

  final Scope scope;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => context.read<ScopeCubit>().refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Company', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _CompanyCard(scope: scope),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Assigned locations',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(width: 8),
              if (scope.unrestrictedCompanyAccess)
                Text(
                  '(all locations)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!scope.hasAssignedLocations)
            const _NoLocations()
          else
            ...scope.assignedLocations.map((l) => _LocationTile(location: l)),
        ],
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.scope});

  final Scope scope;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(Icons.business, color: scheme.onPrimaryContainer),
        ),
        title: Text(scope.company.name),
        subtitle: Text(scope.user.displayName),
        trailing: _RoleBadge(role: scope.role),
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

class _LocationTile extends StatelessWidget {
  const _LocationTile({required this.location});

  final LocationRef location;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(Icons.location_on_outlined, color: scheme.primary),
        title: Text(location.name),
      ),
    );
  }
}

class _NoLocations extends StatelessWidget {
  const _NoLocations();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.wrong_location_outlined, size: 40, color: scheme.outline),
            const SizedBox(height: 12),
            Text('No locations assigned',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'You have not been assigned to any locations yet. Contact your '
              'administrator.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
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
            Icon(Icons.cloud_off,
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
