import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/router/app_routes.dart';
import '../../../auth/presentation/controller/auth_controller.dart';
import '../../data/models/enums.dart';
import '../../data/models/scope.dart';
import 'connection_scope_screen.dart';
import 'scope_cubit.dart';

/// F15 — Company / Tenant Selector. Shows the active company + parent/child
/// indicator and the accessible connected companies.
/// States: single-scope · multiple-accessible · no-connected-company.
class CompanySelectorScreen extends StatelessWidget {
  const CompanySelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ScopeCubit>(
      create: (_) => sl<ScopeCubit>()..load(),
      child: const _CompanySelectorView(),
    );
  }
}

class _CompanySelectorView extends StatelessWidget {
  const _CompanySelectorView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Companies'),
        actions: [
          // Interim entry points into F3/F4 until the F2 Home tab bar lands in
          // Phase 2b.
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
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => sl<AuthController>().logout(),
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
                message: state.errorMessage ?? 'Could not load your scope.',
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
          Text('Active company',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _ActiveCompanyCard(scope: scope),
          const SizedBox(height: 24),
          Text('Connected companies',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (!scope.hasConnectedCompanies)
            const _NoConnectedCompany()
          else
            ...scope.connections.map(
              (c) => _ConnectionTile(scope: scope, connection: c),
            ),
        ],
      ),
    );
  }
}

class _ActiveCompanyCard extends StatelessWidget {
  const _ActiveCompanyCard({required this.scope});

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
        title: Text(scope.activeCompany.name),
        subtitle: Text(
          '${scope.activeTenant.kind.label} tenant · ${scope.activeTenant.name}'
          '${scope.activeLocation != null ? '\n${scope.activeLocation!.name}' : ''}',
        ),
        isThreeLine: scope.activeLocation != null,
        trailing: _TenantTypeBadge(kind: scope.activeTenant.kind),
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.scope, required this.connection});

  final Scope scope;
  final Connection connection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = connection.grantsAccess;
    return Card(
      child: ListTile(
        enabled: enabled,
        leading: CircleAvatar(
          backgroundColor:
              enabled ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
          child: Text(
            connection.connectionType.shortLabel.replaceAll(' ', ''),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: enabled ? scheme.onSecondaryContainer : scheme.outline,
            ),
          ),
        ),
        title: Text(connection.targetCompany.name),
        subtitle: Text(
          '${connection.connectionType.label}\n'
          '${connection.bestPermission.label} · '
          '${connection.scopes.length} area'
          '${connection.scopes.length == 1 ? '' : 's'}'
          '${connection.isEnabled ? '' : ' · Disabled'}',
        ),
        isThreeLine: true,
        trailing: enabled
            ? const Icon(Icons.chevron_right)
            : Icon(Icons.block, color: scheme.error),
        onTap: enabled
            ? () => context.push(
                  AppRoutes.connectionScope,
                  extra: ConnectionScopeArgs(
                    scope: scope,
                    connection: connection,
                  ),
                )
            : null,
      ),
    );
  }
}

class _TenantTypeBadge extends StatelessWidget {
  const _TenantTypeBadge({required this.kind});

  final TenantType kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isParent = kind == TenantType.parent;
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor:
          isParent ? scheme.primaryContainer : scheme.tertiaryContainer,
      label: Text(
        kind.label,
        style: TextStyle(
          color: isParent
              ? scheme.onPrimaryContainer
              : scheme.onTertiaryContainer,
        ),
      ),
    );
  }
}

class _NoConnectedCompany extends StatelessWidget {
  const _NoConnectedCompany();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.link_off, size: 40, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              'No connected companies',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'You only have access to your own company. Cross-tenant '
              'connections are configured by an administrator.',
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
