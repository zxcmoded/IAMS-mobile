import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/router/app_routes.dart';
import '../../data/models/inventory_record.dart';
import '../shared/qty_format.dart';
import '../widgets/offline_badge.dart';
import 'inventory_records_cubit.dart';

/// Lists locally-saved (offline) inventory records, each flagged with an
/// [OfflineBadge]. Read-only and fully offline.
class InventoryRecordsScreen extends StatelessWidget {
  const InventoryRecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<InventoryRecordsCubit>(
      create: (_) => sl<InventoryRecordsCubit>()..load(),
      child: const _InventoryRecordsView(),
    );
  }
}

class _InventoryRecordsView extends StatelessWidget {
  const _InventoryRecordsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: const Text('Offline Inventory'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('records_create'),
        onPressed: () async {
          final saved = await context.push<bool>(AppRoutes.inventoryCreate);
          if (saved == true && context.mounted) {
            context.read<InventoryRecordsCubit>().refresh();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Create Inventory'),
      ),
      body: SafeArea(
        child: BlocBuilder<InventoryRecordsCubit, InventoryRecordsState>(
          builder: (context, state) {
            switch (state.status) {
              case InventoryRecordsStatus.loading:
                return const Center(child: CircularProgressIndicator());
              case InventoryRecordsStatus.error:
                return Center(
                  child: Text(state.errorMessage ?? 'Something went wrong.'),
                );
              case InventoryRecordsStatus.loaded:
                if (state.isEmpty) return const _EmptyState();
                return RefreshIndicator(
                  onRefresh: () =>
                      context.read<InventoryRecordsCubit>().refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.records.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _RecordRow(record: state.records[i]),
                  ),
                );
            }
          },
        ),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final InventoryRecord record;

  @override
  Widget build(BuildContext context) {
    final location = [
      record.warehouseName,
      if (record.rackName != null) record.rackName!,
      if (record.binName != null) record.binName!,
    ].join(' › ');
    return ListTile(
      key: Key('record_${record.id}'),
      title: Row(
        children: [
          Expanded(
            child: Text(location, overflow: TextOverflow.ellipsis),
          ),
          if (record.isOffline) const OfflineBadge(),
        ],
      ),
      subtitle: Text(
        '${record.items.length} SKU(s) · '
        '${formatQty(record.totalQuantity)} total qty',
      ),
      trailing: Text(
        '${record.items.length}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 96),
        Icon(Icons.inventory_2_outlined,
            size: 56, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 16),
        Text('No offline inventory yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Tap "Create Inventory" to record one.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
