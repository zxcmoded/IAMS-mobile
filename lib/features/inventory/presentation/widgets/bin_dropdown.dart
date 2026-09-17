import 'package:flutter/material.dart';

import '../shared/mutation_args.dart';
import '../shared/qty_format.dart';

/// A bin picker over the item's known [bins], labelling each with its short id
/// and current on-hand. Interim label form until bin names are resolved from
/// the master-data hierarchy.
class BinDropdown extends StatelessWidget {
  const BinDropdown({
    super.key,
    required this.label,
    required this.bins,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<BinOption> bins;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (bins.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          'No known bins for this item.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: bins
          .map((b) => DropdownMenuItem<String>(
                value: b.binId,
                child: Text(
                  'Bin ${shortId(b.binId)} · on hand ${formatQty(b.onHand)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(growable: false),
      onChanged: onChanged,
    );
  }
}
