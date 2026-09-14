import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/router/app_routes.dart';
import '../../data/models/access.dart';
import '../../data/models/enums.dart';
import '../../data/models/scope.dart';
import '../widgets/connected_resource_context.dart';
import 'access_cubit.dart';
import 'access_denied_screen.dart';

/// Navigation args for the Cross-Tenant Resource Access screen.
class CrossTenantAccessArgs {
  const CrossTenantAccessArgs({required this.scope, required this.connection});

  final Scope scope;
  final Connection connection;
}

/// F15 — Cross-Tenant Resource Access. Permission-aware actions for a resource
/// in a connected company. Calls `POST /access/evaluate` before offering an
/// action. States: allowed · read-only · access-denied (+ evaluating/error).
class CrossTenantAccessScreen extends StatelessWidget {
  const CrossTenantAccessScreen({super.key, required this.args});

  final CrossTenantAccessArgs args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AccessCubit>(
      create: (_) => sl<AccessCubit>(),
      child: _CrossTenantAccessView(args: args),
    );
  }
}

class _CrossTenantAccessView extends StatefulWidget {
  const _CrossTenantAccessView({required this.args});

  final CrossTenantAccessArgs args;

  @override
  State<_CrossTenantAccessView> createState() => _CrossTenantAccessViewState();
}

class _CrossTenantAccessViewState extends State<_CrossTenantAccessView> {
  PermissionLevel _required = PermissionLevel.write;

  Scope get _scope => widget.args.scope;
  Connection get _connection => widget.args.connection;

  void _evaluate() {
    // Build the resource coordinates from the connection's target company and,
    // when the connection is scoped to a node, that node id — so the demo
    // reflects the real allowed/denied outcome for this connection.
    final resource = ResourceRef(
      companyId: _connection.targetCompany.id,
      locationId: _coordFor(ScopeLevel.location),
      warehouseId: _coordFor(ScopeLevel.warehouse),
      rackId: _coordFor(ScopeLevel.rack),
      binId: _coordFor(ScopeLevel.bin),
      resourceType: 'Asset',
    );
    context.read<AccessCubit>().evaluate(
          AccessRequest(resource: resource, requiredPermission: _required),
        );
  }

  /// Supply the node id of a granted scope at [level], if the connection has
  /// one, so an in-scope request is expressible; other levels are left null.
  String? _coordFor(ScopeLevel level) {
    for (final scope in _connection.scopes) {
      if (scope.level == level && scope.nodeId != null) return scope.nodeId;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resource access')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConnectedResourceContext(
            sourceCompany: _scope.activeCompany,
            sourceTenant: _scope.activeTenant,
            targetCompany: _connection.targetCompany,
            targetTenant: _connection.targetTenant,
            connectionType: _connection.connectionType,
          ),
          const SizedBox(height: 24),
          Text('Required permission',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<PermissionLevel>(
            segments: const [
              ButtonSegment(
                  value: PermissionLevel.read, label: Text('Read')),
              ButtonSegment(
                  value: PermissionLevel.write, label: Text('Write')),
              ButtonSegment(
                  value: PermissionLevel.full, label: Text('Full')),
            ],
            selected: {_required},
            onSelectionChanged: (s) => setState(() => _required = s.first),
          ),
          const SizedBox(height: 16),
          BlocBuilder<AccessCubit, AccessState>(
            builder: (context, state) {
              return FilledButton(
                onPressed: state.isEvaluating ? null : _evaluate,
                child: state.isEvaluating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Evaluate access'),
              );
            },
          ),
          const SizedBox(height: 24),
          BlocBuilder<AccessCubit, AccessState>(
            builder: (context, state) => _resultSection(context, state),
          ),
        ],
      ),
    );
  }

  Widget _resultSection(BuildContext context, AccessState state) {
    switch (state.status) {
      case AccessStatus.initial:
        return const _Hint(
          text: 'Choose a permission level and evaluate to see whether this '
              'action is allowed on the connected company\'s resources.',
        );
      case AccessStatus.evaluating:
        return const SizedBox.shrink();
      case AccessStatus.error:
        return _ResultCard(
          icon: Icons.cloud_off,
          color: Theme.of(context).colorScheme.error,
          title: 'Could not evaluate',
          body: state.errorMessage ?? 'Please try again.',
        );
      case AccessStatus.loaded:
        return _decisionCard(context, state.decision!);
    }
  }

  Widget _decisionCard(BuildContext context, AccessDecision decision) {
    final scheme = Theme.of(context).colorScheme;
    if (decision.isAllowed) {
      return _ResultCard(
        icon: Icons.check_circle,
        color: Colors.green.shade700,
        title: 'Allowed',
        body: 'Effective permission: ${decision.effectivePermission.label}. '
            '${decision.reason.explanation}',
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.edit),
            label: Text('Perform ${_required.label} action'),
            onPressed: () {},
          ),
        ],
      );
    }

    if (decision.canDowngradeToReadOnly) {
      return _ResultCard(
        icon: Icons.visibility,
        color: scheme.tertiary,
        title: 'Read-only',
        body: 'You can view this resource but not perform a '
            '${_required.label} action. '
            'Effective permission: ${decision.effectivePermission.label}.',
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.visibility),
            label: const Text('View (read-only)'),
            onPressed: () {},
          ),
        ],
      );
    }

    // Denied.
    return _ResultCard(
      icon: Icons.block,
      color: scheme.error,
      title: 'Access denied',
      body: decision.reason.explanation,
      actions: [
        FilledButton.tonal(
          onPressed: () => context.push(
            AppRoutes.accessDenied,
            extra: AccessDeniedArgs(
              scope: _scope,
              connection: _connection,
              decision: decision,
            ),
          ),
          child: const Text('View details'),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(title,
                    key: const Key('access_result_title'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: color)),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
    );
  }
}
