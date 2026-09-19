import 'package:dio/dio.dart';

import '../../masterdata/data/models/master_data_page.dart';
import 'models/inventory_item_sync.dart';
import 'models/stock_level_sync.dart';

/// Typed client for the two **offline sync feeds** (`GET /inventory/sync/items`
/// and `GET /inventory/sync/stock-levels`). Distinct from [InventoryApi], which
/// is the interactive list/detail + mutation surface — this client is used only
/// by [InventorySyncService] to hydrate the local SQLite cache.
///
/// Both feeds ride the shared master-data envelope (`{ items, nextCursor,
/// hasMore }`) with the cursor on the **envelope**, not per row — so they reuse
/// [MasterDataPage]. Uses the *authenticated* Dio (Bearer attached; a 401
/// invalidates the session; the shared `ErrorInterceptor` normalizes any
/// response ≥ 300 into a typed `ApiException`, including `400 validation_failed`
/// for a malformed cursor or bad pageSize).
///
/// `cursor` is echoed back verbatim (never constructed/parsed client-side);
/// null/empty query params are omitted so the server sees "absent"
/// (start-of-world) rather than an empty string.
class InventorySyncApi {
  InventorySyncApi(this._dio);

  final Dio _dio;

  Future<MasterDataPage<InventoryItemSync>> getItems({
    String? cursor,
    int? pageSize,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/inventory/sync/items',
      queryParameters: _query(cursor: cursor, pageSize: pageSize),
    );
    return MasterDataPage.fromJson(res.data!, InventoryItemSync.fromJson);
  }

  Future<MasterDataPage<StockLevelSync>> getStockLevels({
    String? cursor,
    int? pageSize,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/inventory/sync/stock-levels',
      queryParameters: _query(cursor: cursor, pageSize: pageSize),
    );
    return MasterDataPage.fromJson(res.data!, StockLevelSync.fromJson);
  }

  Map<String, dynamic> _query({String? cursor, int? pageSize}) => {
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'pageSize': ?pageSize,
      };
}
