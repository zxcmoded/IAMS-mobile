import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../data/models/inventory_record.dart';
import '../shared/qty_format.dart';
import '../widgets/offline_badge.dart';
import 'create_inventory_cubit.dart';

/// The offline-first **Create Inventory** flow: warehouse (required, validated
/// against the current location's local warehouses) → optional rack → optional
/// bin → a repeatable SKU scan/entry loop that accumulates quantities → save.
/// No network is touched at any point.
class CreateInventoryScreen extends StatelessWidget {
  const CreateInventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CreateInventoryCubit>(
      create: (_) => sl<CreateInventoryCubit>(),
      child: const _CreateInventoryView(),
    );
  }
}

class _CreateInventoryView extends StatefulWidget {
  const _CreateInventoryView();

  @override
  State<_CreateInventoryView> createState() => _CreateInventoryViewState();
}

class _CreateInventoryViewState extends State<_CreateInventoryView> {
  final _warehouseController = TextEditingController();
  final _skuController = TextEditingController();
  final _qtyController = TextEditingController();

  @override
  void dispose() {
    _warehouseController.dispose();
    _skuController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  void _validateWarehouse() {
    context
        .read<CreateInventoryCubit>()
        .validateWarehouse(_warehouseController.text);
  }

  /// A "scan" (enter) of the SKU field — increments by one and keeps the field
  /// populated so a rapid sequence of scans keeps accumulating.
  void _scanSku() {
    final code = _skuController.text.trim();
    if (code.isEmpty) return;
    context.read<CreateInventoryCubit>().scanSku(code);
  }

  void _addSkuManual() {
    final code = _skuController.text.trim();
    final qty = double.tryParse(_qtyController.text.trim()) ?? 1;
    context.read<CreateInventoryCubit>().addSkuManual(code, quantity: qty);
    _skuController.clear();
    _qtyController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CreateInventoryCubit, CreateInventoryState>(
      listenWhen: (a, b) => a.saveStatus != b.saveStatus,
      listener: (context, state) {
        if (state.saveStatus == SaveStatus.saved) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              content: Text('Inventory saved offline.'),
            ));
          context.pop(true);
        } else if (state.saveStatus == SaveStatus.error) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(state.saveError ?? 'Could not save.'),
            ));
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.green,
            title: const Text('Create Inventory'),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 12),
                child: Center(child: OfflineBadge()),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _OfflineBanner(),
                const SizedBox(height: 16),
                _WarehouseField(
                  controller: _warehouseController,
                  state: state,
                  onValidate: _validateWarehouse,
                ),
                if (state.hasWarehouse) ...[
                  const SizedBox(height: 16),
                  _RackDropdown(state: state),
                  const SizedBox(height: 16),
                  _BinDropdown(state: state),
                  const SizedBox(height: 24),
                  _SkuEntry(
                    skuController: _skuController,
                    qtyController: _qtyController,
                    state: state,
                    onScan: _scanSku,
                    onAdd: _addSkuManual,
                  ),
                  const SizedBox(height: 16),
                  _LineList(lines: state.lines),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('save_inventory'),
                  onPressed: state.canSave
                      ? () => context.read<CreateInventoryCubit>().save()
                      : null,
                  icon: state.saveStatus == SaveStatus.saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save inventory (offline)'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This inventory is created and saved entirely offline. No internet '
              'is required.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseField extends StatelessWidget {
  const _WarehouseField({
    required this.controller,
    required this.state,
    required this.onValidate,
  });

  final TextEditingController controller;
  final CreateInventoryState state;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) {
    final warehouse = state.warehouse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Warehouse *', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          key: const Key('warehouse_input'),
          controller: controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Scan or enter warehouse code',
            border: const OutlineInputBorder(),
            errorText: state.warehouseError,
            prefixIcon: const Icon(Icons.qr_code_scanner),
            suffixIcon: IconButton(
              key: const Key('warehouse_validate'),
              icon: const Icon(Icons.check),
              tooltip: 'Validate',
              onPressed: onValidate,
            ),
          ),
          onSubmitted: (_) => onValidate(),
        ),
        if (warehouse != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Warehouse: ${warehouse.name}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RackDropdown extends StatelessWidget {
  const _RackDropdown({required this.state});

  final CreateInventoryState state;

  @override
  Widget build(BuildContext context) {
    if (state.racks.isEmpty) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Rack (optional)',
          border: OutlineInputBorder(),
        ),
        child: Text(
          'No racks for this warehouse.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return DropdownButtonFormField<String?>(
      key: const Key('rack_dropdown'),
      initialValue: state.selectedRackId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Rack (optional)',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('None')),
        ...state.racks.map((r) => DropdownMenuItem<String?>(
              value: r.id,
              child: Text(r.name, overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: (v) => context.read<CreateInventoryCubit>().selectRack(v),
    );
  }
}

class _BinDropdown extends StatelessWidget {
  const _BinDropdown({required this.state});

  final CreateInventoryState state;

  @override
  Widget build(BuildContext context) {
    final disabled = state.selectedRackId == null;
    if (disabled || state.bins.isEmpty) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Bin (optional)',
          border: OutlineInputBorder(),
        ),
        child: Text(
          disabled ? 'Select a rack first.' : 'No bins for this rack.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return DropdownButtonFormField<String?>(
      key: const Key('bin_dropdown'),
      initialValue: state.selectedBinId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Bin (optional)',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('None')),
        ...state.bins.map((b) => DropdownMenuItem<String?>(
              value: b.id,
              child: Text(b.name, overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: (v) => context.read<CreateInventoryCubit>().selectBin(v),
    );
  }
}

class _SkuEntry extends StatelessWidget {
  const _SkuEntry({
    required this.skuController,
    required this.qtyController,
    required this.state,
    required this.onScan,
    required this.onAdd,
  });

  final TextEditingController skuController;
  final TextEditingController qtyController;
  final CreateInventoryState state;
  final VoidCallback onScan;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SKUs *', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Scan repeatedly to accumulate quantity, or add with a manual '
          'quantity.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                key: const Key('sku_input'),
                controller: skuController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'Scan or enter SKU',
                  border: const OutlineInputBorder(),
                  errorText: state.skuError,
                  prefixIcon: const Icon(Icons.qr_code_scanner),
                ),
                // Submitting the field = one scan (increments by one), keeping
                // the value for rapid consecutive scans.
                onSubmitted: (_) => onScan(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextField(
                key: const Key('sku_qty'),
                controller: qtyController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Qty',
                  hintText: '1',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('sku_scan'),
                onPressed: onScan,
                icon: const Icon(Icons.add),
                label: const Text('Scan +1'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                key: const Key('sku_add'),
                onPressed: onAdd,
                icon: const Icon(Icons.playlist_add),
                label: const Text('Add SKU'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LineList extends StatelessWidget {
  const _LineList({required this.lines});

  final List<InventoryRecordLine> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No SKUs added yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Added SKUs (${lines.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ...lines.map((l) => _LineRow(line: l)),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final InventoryRecordLine line;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateInventoryCubit>();
    return Card(
      key: Key('line_${line.inventoryItemId}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.sku,
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(line.name,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              key: Key('line_dec_${line.inventoryItemId}'),
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Decrease',
              onPressed: () => cubit.setLineQuantity(
                  line.inventoryItemId, line.quantity - 1),
            ),
            Text(
              formatQty(line.quantity),
              key: Key('line_qty_${line.inventoryItemId}'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            IconButton(
              key: Key('line_inc_${line.inventoryItemId}'),
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Increase',
              onPressed: () => cubit.setLineQuantity(
                  line.inventoryItemId, line.quantity + 1),
            ),
            IconButton(
              key: Key('line_remove_${line.inventoryItemId}'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: () => cubit.removeLine(line.inventoryItemId),
            ),
          ],
        ),
      ),
    );
  }
}
