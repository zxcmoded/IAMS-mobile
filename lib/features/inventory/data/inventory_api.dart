import 'package:dio/dio.dart';

import 'models/stock_count_response.dart';
import 'models/stock_movement_response.dart';

/// Typed client for the F4 inventory **mutation** endpoints. Uses the
/// *authenticated* Dio, so the Bearer token is attached, a 401 invalidates the
/// stored session, and the shared `ErrorInterceptor` normalizes any response
/// ≥ 300 into a typed `ApiException` (including the Phase-2a
/// `stock_version_conflict` / `insufficient_stock` / `stock_count_not_pending`
/// codes).
///
/// There are **no read methods here anymore**: the list/detail/search/filter
/// surfaces are served entirely from local SQLite (`InventoryRepository`), and
/// the only inventory API traffic besides these mutations is the background
/// sync feed (`InventorySyncApi`). This keeps the offline-first guarantee
/// structural — a read path has no API client to call.
///
/// Mutation methods take a client-generated [idempotencyKey] (stable across
/// retries) and optional `base*StockVersion` stamps. **Passing `null` for a
/// base version omits it from the body**, which the server reads as "skip the
/// concurrency check" (last-writer-wins) — the offline outbox omits them on the
/// first online attempt and includes them only when replaying a queued
/// mutation.
class InventoryApi {
  InventoryApi(this._dio);

  final Dio _dio;

  // ---- Mutations ------------------------------------------------------------

  Future<StockMovementResponse> receive({
    required String idempotencyKey,
    required String inventoryItemId,
    required String destinationBinId,
    required double quantity,
    int? baseDestinationStockVersion,
    String? deviceId,
    DateTime? clientCreatedAtUtc,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/inventory/receive',
      data: {
        'idempotencyKey': idempotencyKey,
        'inventoryItemId': inventoryItemId,
        'destinationBinId': destinationBinId,
        'quantity': quantity,
        'baseDestinationStockVersion': ?baseDestinationStockVersion,
        ..._audit(deviceId, clientCreatedAtUtc),
      },
    );
    return StockMovementResponse.fromJson(res.data!);
  }

  Future<StockMovementResponse> transfer({
    required String idempotencyKey,
    required String inventoryItemId,
    required String sourceBinId,
    required String destinationBinId,
    required double quantity,
    int? baseSourceStockVersion,
    int? baseDestinationStockVersion,
    String? deviceId,
    DateTime? clientCreatedAtUtc,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/inventory/transfer',
      data: {
        'idempotencyKey': idempotencyKey,
        'inventoryItemId': inventoryItemId,
        'sourceBinId': sourceBinId,
        'destinationBinId': destinationBinId,
        'quantity': quantity,
        'baseSourceStockVersion': ?baseSourceStockVersion,
        'baseDestinationStockVersion': ?baseDestinationStockVersion,
        ..._audit(deviceId, clientCreatedAtUtc),
      },
    );
    return StockMovementResponse.fromJson(res.data!);
  }

  Future<StockMovementResponse> adjust({
    required String idempotencyKey,
    required String inventoryItemId,
    required String binId,
    required double quantityDelta,
    required String reason,
    int? baseStockVersion,
    String? deviceId,
    DateTime? clientCreatedAtUtc,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/inventory/adjust',
      data: {
        'idempotencyKey': idempotencyKey,
        'inventoryItemId': inventoryItemId,
        'binId': binId,
        'quantityDelta': quantityDelta,
        'reason': reason,
        'baseStockVersion': ?baseStockVersion,
        ..._audit(deviceId, clientCreatedAtUtc),
      },
    );
    return StockMovementResponse.fromJson(res.data!);
  }

  Future<StockCountResponse> count({
    required String idempotencyKey,
    required String inventoryItemId,
    required String binId,
    required double countedQuantity,
    int? baseStockVersion,
    String? deviceId,
    DateTime? clientCreatedAtUtc,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/inventory/counts',
      data: {
        'idempotencyKey': idempotencyKey,
        'inventoryItemId': inventoryItemId,
        'binId': binId,
        'countedQuantity': countedQuantity,
        'baseStockVersion': ?baseStockVersion,
        ..._audit(deviceId, clientCreatedAtUtc),
      },
    );
    return StockCountResponse.fromJson(res.data!);
  }

  Future<StockCountResponse> approveCount(String id) async {
    final res =
        await _dio.post<Map<String, dynamic>>('/inventory/counts/$id/approve');
    return StockCountResponse.fromJson(res.data!);
  }

  Future<StockCountResponse> rejectCount(String id, {String? reason}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/inventory/counts/$id/reject',
      data: {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return StockCountResponse.fromJson(res.data!);
  }

  Map<String, dynamic> _audit(String? deviceId, DateTime? clientCreatedAtUtc) =>
      {
        if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
        if (clientCreatedAtUtc != null)
          'clientCreatedAtUtc': clientCreatedAtUtc.toUtc().toIso8601String(),
      };
}
