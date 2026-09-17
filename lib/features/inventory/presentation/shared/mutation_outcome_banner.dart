import 'package:flutter/material.dart';

import '../../data/models/inventory_enums.dart';
import '../../data/outbox_repository.dart';
import 'qty_format.dart';

/// The inline state shown after a mutation is submitted — the F4 "committed-
/// offline / synced / pending / conflict / error" affordance. Purely a function
/// of the [MutationResult], so every mutation screen renders it consistently.
class MutationOutcomeBanner extends StatelessWidget {
  const MutationOutcomeBanner({super.key, required this.result});

  final MutationResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = _visual(context);
    return Card(
      key: Key('outcome_${result.outcome.name}'),
      color: v.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(v.icon, color: v.foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: v.foreground)),
                  if (v.detail != null) ...[
                    const SizedBox(height: 4),
                    Text(v.detail!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _BannerVisual _visual(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (result.outcome) {
      case MutationOutcome.applied:
        return _BannerVisual(
          icon: Icons.check_circle,
          foreground: Colors.green.shade800,
          background: Colors.green.withValues(alpha: 0.10),
          title: 'Synced',
          detail: _countDetail() ?? 'Applied on the server.',
        );
      case MutationOutcome.replayed:
        return _BannerVisual(
          icon: Icons.check_circle_outline,
          foreground: Colors.green.shade800,
          background: Colors.green.withValues(alpha: 0.10),
          title: 'Already synced',
          detail: 'This action had already been applied — no double effect.',
        );
      case MutationOutcome.queued:
        return _BannerVisual(
          icon: Icons.cloud_off,
          foreground: scheme.tertiary,
          background: scheme.tertiaryContainer.withValues(alpha: 0.4),
          title: 'Committed offline',
          detail: 'Saved on this device and queued — it will sync when you '
              'reconnect.',
        );
      case MutationOutcome.conflict:
        return _BannerVisual(
          icon: Icons.sync_problem,
          foreground: Colors.orange.shade900,
          background: Colors.orange.withValues(alpha: 0.12),
          title: 'Conflict — needs review',
          detail: 'Someone else changed this stock first. Open the item to '
              'review and retry.',
        );
      case MutationOutcome.insufficientStock:
        return _BannerVisual(
          icon: Icons.remove_circle_outline,
          foreground: scheme.error,
          background: scheme.errorContainer.withValues(alpha: 0.4),
          title: 'Not enough stock',
          detail: _insufficientDetail() ?? result.errorMessage,
        );
      case MutationOutcome.rejected:
        return _BannerVisual(
          icon: Icons.error_outline,
          foreground: scheme.error,
          background: scheme.errorContainer.withValues(alpha: 0.4),
          title: 'Couldn\'t be applied',
          detail: result.errorMessage ?? 'The server rejected this action.',
        );
    }
  }

  /// For a stock count, surface the server-computed variance + whether it
  /// auto-applied or parked for approval (never recomputed client-side).
  String? _countDetail() {
    final c = result.count;
    if (c == null) return null;
    final variance = formatSignedQty(c.variance);
    if (c.status.isPendingApproval) {
      return 'Variance $variance is over threshold — parked as Pending '
          'Approval. No stock change yet.';
    }
    if (c.status == StockCountStatus.approved) {
      return 'Approved. Stock set to ${formatQty(c.countedQuantity)}.';
    }
    return 'Within threshold — applied. Variance $variance.';
  }

  String? _insufficientDetail() {
    final available = result.errorMessage;
    return available; // message already carries the server detail
  }
}

class _BannerVisual {
  _BannerVisual({
    required this.icon,
    required this.foreground,
    required this.background,
    required this.title,
    this.detail,
  });

  final IconData icon;
  final Color foreground;
  final Color background;
  final String title;
  final String? detail;
}
