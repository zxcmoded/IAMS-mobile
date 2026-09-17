import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../shared/mutation_args.dart';
import '../shared/mutation_state.dart';
import '../widgets/bin_dropdown.dart';
import '../widgets/mutation_scaffold.dart';
import 'transfer_cubit.dart';

/// F4 Transfer — SKU, quantity, source bin, destination bin. States: draft ·
/// error · pending · synced (inline via the shared outcome banner).
class TransferScreen extends StatelessWidget {
  const TransferScreen({super.key, required this.args});

  final MutationArgs args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TransferCubit>(
      create: (_) => sl<TransferCubit>(),
      child: _TransferView(args: args),
    );
  }
}

class _TransferView extends StatefulWidget {
  const _TransferView({required this.args});

  final MutationArgs args;

  @override
  State<_TransferView> createState() => _TransferViewState();
}

class _TransferViewState extends State<_TransferView> {
  final _qtyController = TextEditingController();
  String? _sourceBinId;
  String? _destinationBinId;

  @override
  void initState() {
    super.initState();
    _sourceBinId = widget.args.presetBinId;
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<TransferCubit>().submit(
          inventoryItemId: widget.args.itemId,
          sourceBinId: _sourceBinId,
          destinationBinId: _destinationBinId,
          quantity: double.tryParse(_qtyController.text.trim()),
          sourceOnHand: widget.args.onHandOf(_sourceBinId),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TransferCubit, MutationState>(
      builder: (context, state) {
        return MutationScaffold(
          title: 'Transfer stock',
          args: widget.args,
          state: state,
          onSubmit: _submit,
          submitLabel: 'Transfer',
          fields: [
            BinDropdown(
              key: const Key('transfer_source_bin'),
              label: 'Source bin',
              bins: widget.args.bins,
              value: _sourceBinId,
              onChanged: (v) => setState(() => _sourceBinId = v),
            ),
            const SizedBox(height: 16),
            BinDropdown(
              key: const Key('transfer_destination_bin'),
              label: 'Destination bin',
              bins: widget.args.bins,
              value: _destinationBinId,
              onChanged: (v) => setState(() => _destinationBinId = v),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('transfer_qty'),
              controller: _qtyController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        );
      },
    );
  }
}
