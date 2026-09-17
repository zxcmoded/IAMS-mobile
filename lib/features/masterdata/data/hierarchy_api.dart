import 'package:dio/dio.dart';

import 'models/bin.dart';
import 'models/company.dart';
import 'models/location.dart';
import 'models/master_data_page.dart';
import 'models/rack.dart';
import 'models/warehouse.dart';

/// Typed client for the five master-data listing endpoints. Uses the
/// *authenticated* Dio, so the Bearer token is attached and a 401 invalidates
/// the stored session (driving the user back to re-activation). No error
/// handling here — the shared
/// `ErrorInterceptor`/`ProblemDetailsParser` on that Dio instance normalizes
/// any response ≥ 300 into a typed `ApiException`.
///
/// `cursor` is echoed back verbatim (never constructed/parsed client-side).
/// Null/empty query params are omitted from the request.
class HierarchyApi {
  HierarchyApi(this._dio);

  final Dio _dio;

  Future<MasterDataPage<Company>> getCompanies({
    String? cursor,
    int? pageSize,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/master-data/companies',
      queryParameters: _query(cursor: cursor, pageSize: pageSize),
    );
    return MasterDataPage.fromJson(res.data!, Company.fromJson);
  }

  Future<MasterDataPage<Location>> getLocations({
    String? parentId,
    String? cursor,
    int? pageSize,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/master-data/locations',
      queryParameters:
          _query(parentId: parentId, cursor: cursor, pageSize: pageSize),
    );
    return MasterDataPage.fromJson(res.data!, Location.fromJson);
  }

  Future<MasterDataPage<Warehouse>> getWarehouses({
    String? parentId,
    String? cursor,
    int? pageSize,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/master-data/warehouses',
      queryParameters:
          _query(parentId: parentId, cursor: cursor, pageSize: pageSize),
    );
    return MasterDataPage.fromJson(res.data!, Warehouse.fromJson);
  }

  Future<MasterDataPage<Rack>> getRacks({
    String? parentId,
    String? cursor,
    int? pageSize,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/master-data/racks',
      queryParameters:
          _query(parentId: parentId, cursor: cursor, pageSize: pageSize),
    );
    return MasterDataPage.fromJson(res.data!, Rack.fromJson);
  }

  Future<MasterDataPage<Bin>> getBins({
    String? parentId,
    String? cursor,
    int? pageSize,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/master-data/bins',
      queryParameters:
          _query(parentId: parentId, cursor: cursor, pageSize: pageSize),
    );
    return MasterDataPage.fromJson(res.data!, Bin.fromJson);
  }

  /// Builds the query map, omitting any null/empty param so the server sees
  /// "absent" (start-of-world / no parent filter) rather than an empty string.
  Map<String, dynamic> _query({
    String? parentId,
    String? cursor,
    int? pageSize,
  }) =>
      {
        if (parentId != null && parentId.isNotEmpty) 'parentId': parentId,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'pageSize': ?pageSize,
      };
}
