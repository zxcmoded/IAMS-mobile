import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import '../../data/models/scope.dart';

/// F15 — Connected Resource Context. A reusable context header showing the
/// tenant/company badge, location hierarchy, and (for cross-tenant views) the
/// source → target context. Other screens embed this rather than re-rendering
/// scope context ad hoc.
///
/// States:
/// * current-tenant   — only [sourceCompany]/[sourceTenant] provided.
/// * connected-tenant — [targetCompany]/[targetTenant] also provided.
class ConnectedResourceContext extends StatelessWidget {
  const ConnectedResourceContext({
    super.key,
    required this.sourceCompany,
    required this.sourceTenant,
    this.targetCompany,
    this.targetTenant,
    this.connectionType,
    this.hierarchy = const [],
  });

  final CompanyRef sourceCompany;
  final TenantRef sourceTenant;
  final CompanyRef? targetCompany;
  final TenantRef? targetTenant;
  final ConnectionType? connectionType;

  /// Ordered hierarchy labels (e.g. ["Main Depot", "Warehouse 3", "Rack A"]).
  final List<String> hierarchy;

  bool get _isConnected => targetCompany != null && targetTenant != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _CompanyBadge(
                    label: 'Current',
                    company: sourceCompany,
                    tenant: sourceTenant,
                  ),
                ),
                if (_isConnected) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward,
                        size: 20, color: scheme.outline),
                  ),
                  Expanded(
                    child: _CompanyBadge(
                      label: 'Connected',
                      company: targetCompany!,
                      tenant: targetTenant!,
                      highlight: true,
                    ),
                  ),
                ],
              ],
            ),
            if (connectionType != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.link, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${connectionType!.shortLabel}  ·  ${connectionType!.label}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ],
            if (hierarchy.isNotEmpty) ...[
              const SizedBox(height: 12),
              _HierarchyBreadcrumb(hierarchy: hierarchy),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompanyBadge extends StatelessWidget {
  const _CompanyBadge({
    required this.label,
    required this.company,
    required this.tenant,
    this.highlight = false,
  });

  final String label;
  final CompanyRef company;
  final TenantRef tenant;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlight ? scheme.primary : scheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.outline, letterSpacing: 0.6),
        ),
        const SizedBox(height: 4),
        Text(
          company.name,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        _TenantChip(tenant: tenant),
      ],
    );
  }
}

class _TenantChip extends StatelessWidget {
  const _TenantChip({required this.tenant});

  final TenantRef tenant;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isParent = tenant.kind == TenantType.parent;
    final bg = isParent ? scheme.primaryContainer : scheme.tertiaryContainer;
    final fg =
        isParent ? scheme.onPrimaryContainer : scheme.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${tenant.kind.label} · ${tenant.name}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}

class _HierarchyBreadcrumb extends StatelessWidget {
  const _HierarchyBreadcrumb({required this.hierarchy});

  final List<String> hierarchy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < hierarchy.length; i++) {
      if (i > 0) {
        children.add(Icon(Icons.chevron_right,
            size: 16, color: scheme.outline));
      }
      children.add(Text(
        hierarchy[i],
        style: Theme.of(context).textTheme.bodySmall,
      ));
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
