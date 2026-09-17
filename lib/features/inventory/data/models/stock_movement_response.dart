import 'package:equatable/equatable.dart';

import 'inventory_enums.dart';

/// The resulting on-hand + version of one affected bin after a mutation. The
/// outbox reconciles its local `stock_version_cache` from these authoritative
/// values (especially the bumped [version]) after every applied write.
class StockLevelState extends Equatable {
  const StockLevelState({
    required this.binId,
    required this.quantityOnHand,
    required this.version,
  });

  final String binId;
  final double quantityOnHand;
  final int version;

  factory StockLevelState.fromJson(Map<String, dynamic> json) =>
      StockLevelState(
        binId: json['binId'] as String,
        quantityOnHand: (json['quantityOnHand'] as num?)?.toDouble() ?? 0,
        version: json['version'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [binId, quantityOnHand, version];
}

/// Shared response of receive / transfer / adjust
/// (`StockMovementResponse`). [replayed] is `true` when this was an idempotent
/// replay of an already-committed mutation — no new effect, so the client must
/// treat it as success (never a double-apply) while still reconciling from
/// [stockLevels].
class StockMovementResponse extends Equatable {
  const StockMovementResponse({
    required this.transactionId,
    required this.transactionType,
    required this.status,
    required this.quantity,
    required this.stockLevels,
    required this.replayed,
    this.adjustmentReason,
  });

  final String transactionId;
  final TransactionType transactionType;
  final MovementStatus status;
  final double quantity;
  final List<StockLevelState> stockLevels;
  final bool replayed;
  final String? adjustmentReason;

  factory StockMovementResponse.fromJson(Map<String, dynamic> json) =>
      StockMovementResponse(
        transactionId: json['transactionId'] as String,
        transactionType:
            TransactionType.fromWire(json['transactionType'] as String?),
        status: MovementStatus.fromWire(json['status'] as String?),
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        stockLevels: (json['stockLevels'] as List<dynamic>? ?? const [])
            .map((e) => StockLevelState.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        replayed: json['replayed'] as bool? ?? false,
        adjustmentReason: json['adjustmentReason'] as String?,
      );

  @override
  List<Object?> get props => [
        transactionId,
        transactionType,
        status,
        quantity,
        stockLevels,
        replayed,
        adjustmentReason,
      ];
}
