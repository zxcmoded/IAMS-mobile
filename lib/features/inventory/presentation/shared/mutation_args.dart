import 'package:equatable/equatable.dart';

import '../detail/inventory_item_cubit.dart';
import '../../data/models/inventory_item_detail.dart';

/// A selectable bin on a mutation form, with the on-hand + version last observed
/// for the current item (so the form can pre-check over-source moves and show
/// context). [version] is null when the bin is known only from a pending
/// mutation.
class BinOption extends Equatable {
  const BinOption({
    required this.binId,
    required this.onHand,
    this.version,
  });

  final String binId;
  final double onHand;
  final int? version;

  @override
  List<Object?> get props => [binId, onHand, version];
}

/// Arguments handed to the four mutation screens (receive/transfer/adjust/
/// count). [bins] are the item's currently-known bins (from item detail),
/// used to populate source/destination pickers and the over-source pre-check.
/// [presetBinId] pre-selects a bin — e.g. one reached by scanning a Location.
class MutationArgs extends Equatable {
  const MutationArgs({
    required this.itemId,
    required this.sku,
    required this.name,
    this.bins = const [],
    this.presetBinId,
  });

  final String itemId;
  final String sku;
  final String name;
  final List<BinOption> bins;
  final String? presetBinId;

  /// Builds args from a loaded item-detail screen, using the effective (server
  /// + pending overlay) per-bin on-hand so the pickers reflect what the user
  /// sees.
  factory MutationArgs.fromDetail(
    InventoryItemDetail detail,
    List<BinStock> bins, {
    String? presetBinId,
  }) =>
      MutationArgs(
        itemId: detail.id,
        sku: detail.sku,
        name: detail.name,
        bins: bins
            .map((b) => BinOption(
                  binId: b.binId,
                  onHand: b.effectiveQty,
                  version: b.version,
                ))
            .toList(growable: false),
        presetBinId: presetBinId,
      );

  double? onHandOf(String? binId) {
    if (binId == null) return null;
    for (final b in bins) {
      if (b.binId == binId) return b.onHand;
    }
    return null;
  }

  @override
  List<Object?> get props => [itemId, sku, name, bins, presetBinId];
}
