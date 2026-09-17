import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../shared/mutation_args.dart';
import '../shared/mutation_state.dart';
import '../widgets/bin_dropdown.dart';
import '../widgets/mutation_scaffold.dart';
import 'adjustment_cubit.dart';

/// F4 Adjustment — a signed quantity delta with a required reason. States:
/// draft · committed · queued (inline via the shared outcome banner).
class AdjustmentScreen extends StatelessWidget {
  const AdjustmentScreen({super.key, required this.args});

  final MutationArgs args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdjustmentCubit>(
      create: (_) => sl<AdjustmentCubit>(),
      child: _AdjustmentView(args: args),
    );
  }
}

class _AdjustmentView extends StatefulWidget {
  const _AdjustmentView({required this.args});

  final MutationArgs args;

  @override
  State<_AdjustmentView> createState() => _AdjustmentViewState();
}

class _AdjustmentViewState extends State<_AdjustmentView> {
  final _deltaController = TextEditingController();
  final _reasonController = TextEditingController();
  String? _binId;

  @override
  void initState() {
    super.initState();
    _binId = widget.args.presetBinId;
  }

  @override
  void dispose() {
    _deltaController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<AdjustmentCubit>().submit(
          inventoryItemId: widget.args.itemId,
          binId: _binId,
          quantityDelta: double.tryParse(_deltaController.text.trim()),
          reason: _reasonController.text,
          binOnHand: widget.args.onHandOf(_binId),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdjustmentCubit, MutationState>(
      builder: (context, state) {
        return MutationScaffold(
          title: 'Adjust stock',
          args: widget.args,
          state: state,
          onSubmit: _submit,
          submitLabel: 'Apply adjustment',
          fields: [
            BinDropdown(
              key: const Key('adjust_bin'),
              label: 'Bin',
              bins: widget.args.bins,
              value: _binId,
              onChanged: (v) => setState(() => _binId = v),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('adjust_delta'),
              controller: _deltaController,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Quantity change (e.g. -3 or 5)',
                helperText: 'Signed, non-zero. Result must stay at or above 0.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('adjust_reason'),
              controller: _reasonController,
              maxLength: 400,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
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
