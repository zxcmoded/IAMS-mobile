import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/router/app_routes.dart';
import '../../data/inventory_repository.dart';
import '../../data/models/inventory_enums.dart';
import '../../data/models/inventory_item_detail.dart';
import '../../data/models/outbox_entry.dart';
import '../../data/outbox_repository.dart';
import '../shared/mutation_args.dart';
import '../shared/qty_format.dart';
import 'inventory_item_cubit.dart';

/// F4 Item Detail — identity, qty by bin (with pending overlay), movement
/// history, and the receive/transfer/adjust/count actions. States: online ·
/// offline. Pending/conflicted queued mutations surface inline with review
/// affordances.
class InventoryItemScreen extends StatelessWidget {
  const InventoryItemScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<InventoryItemCubit>(
      create: (_) => InventoryItemCubit(
        sl<InventoryRepository>(),
        sl<OutboxRepository>(),
        itemId: itemId,
      )..load(),
      child: const _ItemView(),
    );
  }
}

class _ItemView extends StatelessWidget {
  const _ItemView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item'),
        actions: [
          BlocBuilder<InventoryItemCubit, InventoryItemState>(
            buildWhen: (a, b) => a.hasPending != b.hasPending,
            builder: (context, state) => state.hasPending
                ? IconButton(
                    tooltip: 'Sync pending',
                    icon: const Icon(Icons.sync),
                    onPressed: () =>
                        context.read<InventoryItemCubit>().syncNow(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<InventoryItemCubit, InventoryItemState>(
          builder: (context, state) {
            switch (state.status) {
              case ItemDetailStatus.loading:
                return const Center(child: CircularProgressIndicator());
              case ItemDetailStatus.notFound:
                return const _NotFoundState();
              case ItemDetailStatus.error:
                return _ErrorState(
                  message: state.errorMessage ?? 'Could not load this item.',
                  onRetry: () => context.read<InventoryItemCubit>().refresh(),
                );
              case ItemDetailStatus.loaded:
                return _LoadedBody(state: state);
            }
          },
        ),
      ),
    );
  }
}

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({required this.state});

  final InventoryItemState state;

  MutationArgs _args(BuildContext context, {String? presetBinId}) {
    final detail = state.detail;
    if (detail != null) {
      return MutationArgs.fromDetail(detail, state.bins,
          presetBinId: presetBinId);
    }
    // Offline: no authoritative detail — build from the cubit id + cached bins.
    final cubit = context.read<InventoryItemCubit>();
    return MutationArgs(
      itemId: cubit.itemId,
      sku: shortId(cubit.itemId),
      name: 'Item ${shortId(cubit.itemId)}',
      bins: state.bins
          .map((b) => BinOption(
              binId: b.binId, onHand: b.effectiveQty, version: b.version))
          .toList(growable: false),
      presetBinId: presetBinId,
    );
  }

  Future<void> _go(BuildContext context, String route) async {
    await context.push(route, extra: _args(context));
    // Returning from a mutation screen may have queued/applied something —
    // reload to reflect it.
    if (context.mounted) context.read<InventoryItemCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final detail = state.detail;
    return RefreshIndicator(
      onRefresh: () => context.read<InventoryItemCubit>().refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _IdentityCard(detail: detail, state: state),
          const SizedBox(height: 16),
          _ActionsBar(onTap: (route) => _go(context, route)),
          const SizedBox(height: 24),
          Text('Stock by bin', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _StockByBin(state: state),
          if (state.pending.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Pending sync', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...state.pending.map((e) => _PendingRow(entry: e)),
          ],
          const SizedBox(height: 24),
          Text('Recent movements',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Movements(detail: detail),
        ],
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.detail, required this.state});

  final InventoryItemDetail? detail;
  final InventoryItemState state;

  @override
  Widget build(BuildContext context) {
    final total = detail?.totalQuantityOnHand ??
        state.bins.fold<double>(0, (sum, b) => sum + b.effectiveQty);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail?.name ?? 'Offline item',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            if (detail != null)
              Text('SKU ${detail!.sku}'
                  '${detail!.barcode != null ? ' · ${detail!.barcode}' : ''}'),
            if (detail?.category != null) Text(detail!.category!),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Total on hand: ',
                    style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  '${formatQty(total)}'
                  '${detail?.unitOfMeasure != null ? ' ${detail!.unitOfMeasure}' : ''}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionsBar extends StatelessWidget {
  const _ActionsBar({required this.onTap});

  final void Function(String route) onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _action(context, 'Receive', Icons.call_received, AppRoutes.receive,
            'action_receive'),
        _action(context, 'Transfer', Icons.swap_horiz, AppRoutes.transfer,
            'action_transfer'),
        _action(context, 'Count', Icons.checklist, AppRoutes.stockCount,
            'action_count'),
        _action(context, 'Adjust', Icons.tune, AppRoutes.adjust,
            'action_adjust'),
      ],
    );
  }

  Widget _action(BuildContext context, String label, IconData icon,
      String route, String key) {
    return OutlinedButton.icon(
      key: Key(key),
      onPressed: () => onTap(route),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _StockByBin extends StatelessWidget {
  const _StockByBin({required this.state});

  final InventoryItemState state;

  @override
  Widget build(BuildContext context) {
    if (state.bins.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No stock recorded in any bin.'),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final bin in state.bins)
            ListTile(
              key: Key('bin_${bin.binId}'),
              dense: true,
              leading: const Icon(Icons.grid_view),
              title: Text('Bin ${shortId(bin.binId)}'),
              subtitle: bin.hasPending
                  ? Text('includes pending ${formatSignedQty(bin.pendingDelta)}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.tertiary))
                  : null,
              trailing: Text(
                formatQty(bin.effectiveQty),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.entry});

  final OutboxEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = context.select<InventoryItemCubit, bool>(
        (c) => c.state.busyKey == entry.idempotencyKey);
    final (icon, color, label) = switch (entry.status) {
      OutboxStatus.pending => (Icons.cloud_upload, scheme.tertiary, 'Queued'),
      OutboxStatus.conflict => (
          Icons.sync_problem,
          Colors.orange.shade900,
          'Conflict'
        ),
      OutboxStatus.failed => (Icons.error_outline, scheme.error, 'Failed'),
      OutboxStatus.synced => (Icons.check, Colors.green, 'Synced'),
    };
    return Card(
      child: ListTile(
        key: Key('pending_${entry.idempotencyKey}'),
        leading: Icon(icon, color: color),
        title: Text('${entry.kind.label} · $label'),
        subtitle: Text(
          entry.lastErrorMessage ??
              (entry.status == OutboxStatus.pending
                  ? 'Waiting to sync'
                  : 'Committed ${entry.createdAtUtc.toLocal()}'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: busy
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : entry.status.needsAttention
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('retry_${entry.idempotencyKey}'),
                        tooltip: 'Retry',
                        icon: const Icon(Icons.refresh),
                        onPressed: () => context
                            .read<InventoryItemCubit>()
                            .retry(entry.idempotencyKey),
                      ),
                      IconButton(
                        key: Key('discard_${entry.idempotencyKey}'),
                        tooltip: 'Discard',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => context
                            .read<InventoryItemCubit>()
                            .discard(entry.idempotencyKey),
                      ),
                    ],
                  )
                : null,
      ),
    );
  }
}

class _Movements extends StatelessWidget {
  const _Movements({required this.detail});

  final InventoryItemDetail? detail;

  @override
  Widget build(BuildContext context) {
    final movements = detail?.movements ?? const [];
    if (movements.isEmpty) {
      // Movement history rides `InventoryTransactions`, which isn't part of the
      // offline sync yet — so it is never available in this local-only view.
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text("Movement history isn't available offline."),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final m in movements)
            ListTile(
              dense: true,
              leading: Icon(_iconFor(m.transactionType)),
              title: Text(m.transactionType.label),
              subtitle: Text(
                '${m.createdAtUtc.toLocal()}'
                '${m.adjustmentReason != null ? ' · ${m.adjustmentReason}' : ''}',
              ),
              trailing: Text(formatQty(m.quantity)),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(TransactionType t) => switch (t) {
        TransactionType.receive => Icons.call_received,
        TransactionType.transfer => Icons.swap_horiz,
        TransactionType.adjustment => Icons.tune,
        TransactionType.unknown => Icons.history,
      };
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('Item not available',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'This item isn\'t in your accessible scope, or no longer exists.',
              textAlign: TextAlign.center,
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
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
