import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/router/app_routes.dart';
import '../../data/models/inventory_enums.dart';
import '../../data/models/inventory_item.dart';
import '../shared/qty_format.dart';
import 'inventory_list_cubit.dart';

/// F4 Inventory List — search, filter pills, item rows with qty. States:
/// populated · empty · low/zero-stock flagged · error.
class InventoryListScreen extends StatelessWidget {
  const InventoryListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<InventoryListCubit>(
      create: (_) => sl<InventoryListCubit>()..load(),
      child: const _InventoryListView(),
    );
  }
}

class _InventoryListView extends StatefulWidget {
  const _InventoryListView();

  @override
  State<_InventoryListView> createState() => _InventoryListViewState();
}

class _InventoryListViewState extends State<_InventoryListView> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      context.read<InventoryListCubit>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: const Text('Inventory'),
        actions: [
          IconButton(
            tooltip: 'Scan',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => context.push(AppRoutes.scanner),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                key: const Key('inventory_search'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search SKU, name, or barcode',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      context.read<InventoryListCubit>().setSearch('');
                    },
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (q) =>
                    context.read<InventoryListCubit>().setSearch(q),
              ),
            ),
            const _FilterPills(),
            const Divider(height: 1),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    return BlocBuilder<InventoryListCubit, InventoryListState>(
      builder: (context, state) {
        switch (state.status) {
          case InventoryListStatus.initial:
          case InventoryListStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case InventoryListStatus.error:
            return _ErrorState(
              message: state.errorMessage ?? 'Could not load inventory.',
              onRetry: () => context.read<InventoryListCubit>().refresh(),
            );
          case InventoryListStatus.loaded:
            if (state.isEmpty) return const _EmptyState();
            return RefreshIndicator(
              onRefresh: () => context.read<InventoryListCubit>().refresh(),
              child: ListView.separated(
                controller: _scrollController,
                itemCount: state.items.length + (state.hasMore ? 1 : 0),
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index >= state.items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _ItemRow(item: state.items[index]);
                },
              ),
            );
        }
      },
    );
  }
}

class _FilterPills extends StatelessWidget {
  const _FilterPills();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryListCubit, InventoryListState>(
      buildWhen: (a, b) => a.filter != b.filter,
      builder: (context, state) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: InventoryFilter.values.map((f) {
              final selected = f == state.filter;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  key: Key('filter_${f.name}'),
                  label: Text(f.label),
                  selected: selected,
                  onSelected: (_) =>
                      context.read<InventoryListCubit>().setFilter(f),
                ),
              );
            }).toList(growable: false),
          ),
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final zero = item.isOutOfStock;
    return ListTile(
      key: Key('item_${item.id}'),
      title: Text(item.name),
      subtitle: Text('SKU ${item.sku}'
          '${item.category != null ? ' · ${item.category}' : ''}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatQty(item.totalQuantityOnHand),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: zero ? scheme.error : null,
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (item.unitOfMeasure != null)
            Text(item.unitOfMeasure!,
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      onTap: () => context.push(
        '${AppRoutes.inventoryItem}?id=${item.id}',
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
        Text('No items match',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Try a different search or filter.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      ],
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
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
