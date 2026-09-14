import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../data/models/enums.dart';
import '../../data/models/scope.dart';
import '../access/cross_tenant_access_screen.dart';
import '../widgets/connected_resource_context.dart';

/// Navigation args for the Connection Scope screen.
class ConnectionScopeArgs {
  const ConnectionScopeArgs({required this.scope, required this.connection});

  final Scope scope;
  final Connection connection;
}

/// F15 — Connection Scope. Display-only view of a single connection: connected
/// company, connection type, permission level, and the accessible hierarchy
/// (company · location · warehouse · rack · bin). Driven entirely by /me/scope.
class ConnectionScopeScreen extends StatelessWidget {
  const ConnectionScopeScreen({super.key, required this.args});

  final ConnectionScopeArgs args;

  @override
  Widget build(BuildContext context) {
    final scope = args.scope;
    final connection = args.connection;

    return Scaffold(
      appBar: AppBar(title: Text(connection.targetCompany.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConnectedResourceContext(
            sourceCompany: scope.activeCompany,
            sourceTenant: scope.activeTenant,
            targetCompany: connection.targetCompany,
            targetTenant: connection.targetTenant,
            connectionType: connection.connectionType,
          ),
          const SizedBox(height: 16),
          _DetailCard(connection: connection),
          const SizedBox(height: 16),
          _HierarchyCard(connection: connection),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.travel_explore),
            label: const Text('Check resource access'),
            onPressed: () => context.push(
              AppRoutes.crossTenantAccess,
              extra: CrossTenantAccessArgs(
                scope: scope,
                connection: connection,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(context, 'Connection type', connection.connectionType.label),
            _row(context, 'Status',
                connection.isEnabled ? 'Enabled' : 'Disabled'),
            _row(context, 'Default permission',
                connection.permissionLevel.label),
            _row(context, 'Granted areas', '${connection.scopes.length}'),
            _row(context, 'Policy version', '${connection.policyVersion}',
                last: true),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline)),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _HierarchyCard extends StatelessWidget {
  const _HierarchyCard({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accessible hierarchy',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              connection.scopes.isEmpty
                  ? 'This connection grants no areas yet.'
                  : 'Access is granted at each area below (and is inherited '
                      'downward to its children).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (connection.scopes.isEmpty)
              const _EmptyScopes()
            else
              ...connection.scopes.map((s) => _ScopeRow(scope: s)),
          ],
        ),
      ),
    );
  }
}

/// One granted node: hierarchy level + the permission that applies there.
class _ScopeRow extends StatelessWidget {
  const _ScopeRow({required this.scope});

  final ConnectionScope scope;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(_iconFor(scope.level), size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scope.level.label,
                    style: Theme.of(context).textTheme.bodyMedium),
                if (scope.level != ScopeLevel.company)
                  Text(
                    'Inherited downward',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.outline,
                        ),
                  ),
              ],
            ),
          ),
          _PermissionChip(permission: scope.permissionLevel),
        ],
      ),
    );
  }

  IconData _iconFor(ScopeLevel level) {
    switch (level) {
      case ScopeLevel.company:
        return Icons.business;
      case ScopeLevel.location:
        return Icons.location_on_outlined;
      case ScopeLevel.warehouse:
        return Icons.warehouse_outlined;
      case ScopeLevel.rack:
        return Icons.shelves;
      case ScopeLevel.bin:
        return Icons.inventory_2_outlined;
      case ScopeLevel.unknown:
        return Icons.help_outline;
    }
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({required this.permission});

  final PermissionLevel permission;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        permission.label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}

class _EmptyScopes extends StatelessWidget {
  const _EmptyScopes();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.remove_circle_outline, size: 18, color: scheme.outline),
        const SizedBox(width: 10),
        Text('No areas granted',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.outline)),
      ],
    );
  }
}
