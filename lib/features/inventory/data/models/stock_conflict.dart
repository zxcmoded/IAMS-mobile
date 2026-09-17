import 'package:equatable/equatable.dart';

/// One entry of a `409 stock_version_conflict` body's `conflicts[]`. Carries
/// the current server state for an affected bin so the outbox can rebase (store
/// the fresh version + on-hand into its cache) without another round-trip.
class StockConflict extends Equatable {
  const StockConflict({
    required this.binId,
    required this.expectedVersion,
    required this.currentVersion,
    required this.currentQuantityOnHand,
  });

  final String binId;
  final int expectedVersion;
  final int currentVersion;
  final double currentQuantityOnHand;

  factory StockConflict.fromJson(Map<String, dynamic> json) => StockConflict(
        binId: json['binId'] as String,
        expectedVersion: json['expectedVersion'] as int? ?? 0,
        currentVersion: json['currentVersion'] as int? ?? 0,
        currentQuantityOnHand:
            (json['currentQuantityOnHand'] as num?)?.toDouble() ?? 0,
      );

  /// Parses the `conflicts` extension member off an [ApiException.extensions]
  /// map. Tolerates absence/shape drift by returning an empty list.
  static List<StockConflict> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => StockConflict.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  @override
  List<Object?> get props =>
      [binId, expectedVersion, currentVersion, currentQuantityOnHand];
}
