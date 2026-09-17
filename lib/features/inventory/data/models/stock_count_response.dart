import 'package:equatable/equatable.dart';

import 'inventory_enums.dart';

/// Response of `POST /api/inventory/counts` (and approve/reject). The
/// [variance] and [varianceThreshold] are **server-computed** — the client
/// displays them verbatim and never recomputes the variance locally. When
/// [status] is [StockCountStatus.pendingApproval] there was **no stock change**;
/// the UI presents that as a distinct outcome, not an error.
class StockCountResponse extends Equatable {
  const StockCountResponse({
    required this.id,
    required this.status,
    required this.countedQuantity,
    required this.systemQuantity,
    required this.variance,
    required this.varianceThreshold,
    required this.varianceThresholdType,
    required this.stockVersion,
    required this.replayed,
    this.adjustmentTransactionId,
  });

  final String id;
  final StockCountStatus status;
  final double countedQuantity;
  final double systemQuantity;
  final double variance;
  final double varianceThreshold;
  final VarianceThresholdType varianceThresholdType;
  final int stockVersion;
  final bool replayed;
  final String? adjustmentTransactionId;

  factory StockCountResponse.fromJson(Map<String, dynamic> json) =>
      StockCountResponse(
        id: json['id'] as String,
        status: StockCountStatus.fromWire(json['status'] as String?),
        countedQuantity: (json['countedQuantity'] as num?)?.toDouble() ?? 0,
        systemQuantity: (json['systemQuantity'] as num?)?.toDouble() ?? 0,
        variance: (json['variance'] as num?)?.toDouble() ?? 0,
        varianceThreshold: (json['varianceThreshold'] as num?)?.toDouble() ?? 0,
        varianceThresholdType: VarianceThresholdType.fromWire(
            json['varianceThresholdType'] as String?),
        stockVersion: json['stockVersion'] as int? ?? 0,
        replayed: json['replayed'] as bool? ?? false,
        adjustmentTransactionId: json['adjustmentTransactionId'] as String?,
      );

  @override
  List<Object?> get props => [
        id,
        status,
        countedQuantity,
        systemQuantity,
        variance,
        varianceThreshold,
        varianceThresholdType,
        stockVersion,
        replayed,
        adjustmentTransactionId,
      ];
}
