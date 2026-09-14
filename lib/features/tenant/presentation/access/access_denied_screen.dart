import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../data/models/access.dart';
import '../../data/models/enums.dart';
import '../../data/models/scope.dart';
import '../widgets/connected_resource_context.dart';

/// Navigation args for the Access Denied screen.
class AccessDeniedArgs {
  const AccessDeniedArgs({
    required this.scope,
    required this.decision,
    this.connection,
  });

  final Scope scope;
  final AccessDecision decision;
  final Connection? connection;
}

/// F15 — Access Denied. Shows the reason (mapped from the `reason` enum),
/// current scope, and a return/switch action.
/// States: disabled-connection · outside-location-scope · insufficient-permission.
class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key, required this.args});

  final AccessDeniedArgs args;

  @override
  Widget build(BuildContext context) {
    final decision = args.decision;
    final display = _AccessDeniedDisplay.fromReason(decision.reason);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Access denied')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Icon(display.icon, size: 64, color: scheme.error),
                const SizedBox(height: 16),
                Text(
                  display.title,
                  key: const Key('access_denied_title'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  decision.reason.explanation,
                  key: const Key('access_denied_reason'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Current scope',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          ConnectedResourceContext(
            sourceCompany: args.scope.activeCompany,
            sourceTenant: args.scope.activeTenant,
            targetCompany: args.connection?.targetCompany,
            targetTenant: args.connection?.targetTenant,
            connectionType: args.connection?.connectionType,
          ),
          const SizedBox(height: 16),
          _EffectivePermissionRow(decision: decision),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.arrow_back),
            label: const Text('Return'),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Switch company'),
            onPressed: () => context.go(AppRoutes.companies),
          ),
        ],
      ),
    );
  }
}

class _EffectivePermissionRow extends StatelessWidget {
  const _EffectivePermissionRow({required this.decision});

  final AccessDecision decision;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.shield_outlined),
        title: const Text('Effective permission'),
        trailing: Text(
          decision.effectivePermission.label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

/// Maps the contract's denial `reason` to the F15 Access Denied UI states.
class _AccessDeniedDisplay {
  const _AccessDeniedDisplay({required this.title, required this.icon});

  final String title;
  final IconData icon;

  factory _AccessDeniedDisplay.fromReason(AccessReason reason) {
    switch (reason) {
      case AccessReason.connectionDisabled:
        // disabled-connection
        return const _AccessDeniedDisplay(
          title: 'Connection disabled',
          icon: Icons.link_off,
        );
      case AccessReason.outOfScope:
        // outside-location-scope
        return const _AccessDeniedDisplay(
          title: 'Outside your location scope',
          icon: Icons.wrong_location_outlined,
        );
      case AccessReason.insufficientPermission:
        // insufficient-permission
        return const _AccessDeniedDisplay(
          title: 'Insufficient permission',
          icon: Icons.lock_outline,
        );
      case AccessReason.noConnection:
        return const _AccessDeniedDisplay(
          title: 'No connected company',
          icon: Icons.link_off,
        );
      case AccessReason.sameTenant:
      case AccessReason.connectionGranted:
      case AccessReason.unknown:
        return const _AccessDeniedDisplay(
          title: 'Access denied',
          icon: Icons.block,
        );
    }
  }
}
