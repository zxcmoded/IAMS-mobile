import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../shared/mutation_args.dart';
import '../shared/mutation_state.dart';
import '../widgets/bin_dropdown.dart';
import '../widgets/mutation_scaffold.dart';
import 'stock_count_cubit.dart';

/// F4 Stock Count — a counted quantity for one bin. Variance is server-computed;
/// the outcome banner shows within-threshold (auto-applied) vs over-threshold
/// (PendingApproval, no stock change yet). States handled inline.
class StockCountScreen extends StatelessWidget {
  const StockCountScreen({super.key, required this.args});

  final MutationArgs args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<StockCountCubit>(
      create: (_) => sl<StockCountCubit>(),
      child: _StockCountView(args: args),
    );
  }
}

class _StockCountView extends StatefulWidget {
  const _StockCountView({required this.args});

  final MutationArgs args;

  @override
  State<_StockCountView> createState() => _StockCountViewState();
}

class _StockCountViewState extends State<_StockCountView> {
  final _countController = TextEditingController();
  String? _binId;

  @override
  void initState() {
    super.initState();
    _binId = widget.args.presetBinId;
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<StockCountCubit>().submit(
          inventoryItemId: widget.args.itemId,
          binId: _binId,
          countedQuantity: double.tryParse(_countController.text.trim()),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StockCountCubit, MutationState>(
      builder: (context, state) {
        return MutationScaffold(
          title: 'Stock count',
          args: widget.args,
          state: state,
          onSubmit: _submit,
          submitLabel: 'Submit count',
          fields: [
            BinDropdown(
              key: const Key('count_bin'),
              label: 'Bin',
              bins: widget.args.bins,
              value: _binId,
              onChanged: (v) => setState(() => _binId = v),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('count_qty'),
              controller: _countController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Counted quantity',
                helperText: 'The variance vs system stock is computed by the '
                    'server.',
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
