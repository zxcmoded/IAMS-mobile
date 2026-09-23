import 'package:flutter/material.dart';

/// A small "Offline" pill shown on locally-created inventory records that have
/// not been synced. Purely presentational — the source of truth is the record's
/// `isOffline` flag.
class OfflineBadge extends StatelessWidget {
  const OfflineBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('offline_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 14, color: scheme.onTertiaryContainer),
          const SizedBox(width: 4),
          Text(
            'Offline',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
