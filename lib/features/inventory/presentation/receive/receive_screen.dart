import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../shared/mutation_args.dart';
import '../shared/mutation_state.dart';
import '../widgets/bin_dropdown.dart';
import '../widgets/mutation_scaffold.dart';
import 'receive_cubit.dart';

/// F4 Receiving — scan/select a SKU (passed in via [MutationArgs]), a quantity,
/// and a destination bin. States: draft · validation-error · committed-offline
/// · synced (all rendered inline via the shared outcome banner).
class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key, required this.args});

  final MutationArgs args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReceiveCubit>(
      create: (_) => sl<ReceiveCubit>(),
      child: _ReceiveView(args: args),
    );
  }
}

class _ReceiveView extends StatefulWidget {
  const _ReceiveView({required this.args});

  final MutationArgs args;

  @override
  State<_ReceiveView> createState() => _ReceiveViewState();
}

class _ReceiveViewState extends State<_ReceiveView> {
  final _qtyController = TextEditingController();
  String? _binId;

  @override
  void initState() {
    super.initState();
    _binId = widget.args.presetBinId;
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<ReceiveCubit>().submit(
          inventoryItemId: widget.args.itemId,
          destinationBinId: _binId,
          quantity: double.tryParse(_qtyController.text.trim()),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReceiveCubit, MutationState>(
      builder: (context, state) {
        return MutationScaffold(
          title: 'Receive stock',
          args: widget.args,
          state: state,
          onSubmit: _submit,
          submitLabel: 'Receive',
          fields: [
            BinDropdown(
              key: const Key('receive_bin'),
              label: 'Destination bin',
              bins: widget.args.bins,
              value: _binId,
              onChanged: (v) => setState(() => _binId = v),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('receive_qty'),
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
