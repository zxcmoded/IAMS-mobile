import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'inventory_enums.dart';

/// One queued offline-first mutation. Persisted to the `outbox_mutation` table
/// so a mutation committed while offline survives an app restart and is
/// replayed — with the **same** [idempotencyKey] — on reconnect. The server
/// de-dupes a replay via that key (`"replayed": true`), so a partial prior
/// success is never double-applied.
///
/// [payload] is the canonical wire body **including** any stamped
/// `base*StockVersion` fields. The first push attempt strips those base
/// versions (a fresh online action is last-writer-wins); every subsequent
/// replay includes them so a real concurrent change surfaces as
/// `409 stock_version_conflict` instead of silently clobbering.
class OutboxEntry extends Equatable {
  const OutboxEntry({
    required this.idempotencyKey,
    required this.kind,
    required this.inventoryItemId,
    required this.payload,
    required this.status,
    required this.createdAtUtc,
    this.attemptCount = 0,
    this.updatedAtUtc,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.response,
  });

  final String idempotencyKey;
  final MutationKind kind;
  final String inventoryItemId;
  final Map<String, dynamic> payload;
  final OutboxStatus status;
  final DateTime createdAtUtc;
  final int attemptCount;
  final DateTime? updatedAtUtc;
  final String? lastErrorCode;
  final String? lastErrorMessage;

  /// The last server response (success body) as raw JSON, kept for audit /
  /// display. Null until first accepted.
  final Map<String, dynamic>? response;

  /// True once at least one push has been attempted — the signal that the next
  /// push is a **replay** and must therefore include the stamped base versions.
  bool get isReplay => attemptCount > 0;

  /// The signed per-bin quantity change this mutation represents, for the
  /// item-detail read-time overlay (observed on-hand + Σ pending deltas). Empty
  /// for [MutationKind.count], which is an absolute set whose outcome depends on
  /// the server's variance adjudication — not a client-known delta.
  Map<String, double> pendingBinDeltas() {
    double q(String k) => (payload[k] as num?)?.toDouble() ?? 0;
    switch (kind) {
      case MutationKind.receive:
        return {payload['destinationBinId'] as String: q('quantity')};
      case MutationKind.transfer:
        return {
          payload['sourceBinId'] as String: -q('quantity'),
          payload['destinationBinId'] as String: q('quantity'),
        };
      case MutationKind.adjust:
        return {payload['binId'] as String: q('quantityDelta')};
      case MutationKind.count:
        return const {};
    }
  }

  OutboxEntry copyWith({
    OutboxStatus? status,
    int? attemptCount,
    DateTime? updatedAtUtc,
    Map<String, dynamic>? payload,
    Object? lastErrorCode = _unset,
    Object? lastErrorMessage = _unset,
    Object? response = _unset,
  }) =>
      OutboxEntry(
        idempotencyKey: idempotencyKey,
        kind: kind,
        inventoryItemId: inventoryItemId,
        payload: payload ?? this.payload,
        status: status ?? this.status,
        createdAtUtc: createdAtUtc,
        attemptCount: attemptCount ?? this.attemptCount,
        updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
        lastErrorCode: identical(lastErrorCode, _unset)
            ? this.lastErrorCode
            : lastErrorCode as String?,
        lastErrorMessage: identical(lastErrorMessage, _unset)
            ? this.lastErrorMessage
            : lastErrorMessage as String?,
        response: identical(response, _unset)
            ? this.response
            : response as Map<String, dynamic>?,
      );

  static const Object _unset = Object();

  factory OutboxEntry.fromRow(Map<String, Object?> row) => OutboxEntry(
        idempotencyKey: row['idempotency_key'] as String,
        kind: MutationKind.fromWire(row['kind'] as String),
        inventoryItemId: row['inventory_item_id'] as String,
        payload: (jsonDecode(row['payload'] as String) as Map)
            .cast<String, dynamic>(),
        status: OutboxStatus.fromWire(row['status'] as String?),
        createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
        attemptCount: (row['attempt_count'] as int?) ?? 0,
        updatedAtUtc: row['updated_at_utc'] == null
            ? null
            : DateTime.parse(row['updated_at_utc'] as String).toUtc(),
        lastErrorCode: row['last_error_code'] as String?,
        lastErrorMessage: row['last_error_message'] as String?,
        response: row['response_json'] == null
            ? null
            : (jsonDecode(row['response_json'] as String) as Map)
                .cast<String, dynamic>(),
      );

  Map<String, Object?> toRow() => {
        'idempotency_key': idempotencyKey,
        'kind': kind.wire,
        'inventory_item_id': inventoryItemId,
        'payload': jsonEncode(payload),
        'status': status.wire,
        'created_at_utc': createdAtUtc.toIso8601String(),
        'attempt_count': attemptCount,
        'updated_at_utc': updatedAtUtc?.toIso8601String(),
        'last_error_code': lastErrorCode,
        'last_error_message': lastErrorMessage,
        'response_json': response == null ? null : jsonEncode(response),
      };

  @override
  List<Object?> get props => [
        idempotencyKey,
        kind,
        inventoryItemId,
        payload,
        status,
        createdAtUtc,
        attemptCount,
        updatedAtUtc,
        lastErrorCode,
        lastErrorMessage,
        response,
      ];
}
