import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_api.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

Response<Map<String, dynamic>> _res(Map<String, dynamic> body) =>
    Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: '/'),
      data: body,
      statusCode: 200,
    );

void main() {
  late MockDio dio;
  late HierarchyApi api;

  setUp(() {
    dio = MockDio();
    api = HierarchyApi(dio);
  });

  Map<String, dynamic>? capturedQuery() =>
      verify(() => dio.get<Map<String, dynamic>>(
            any(),
            queryParameters: captureAny(named: 'queryParameters'),
          )).captured.single as Map<String, dynamic>?;

  group('query-parameter construction', () {
    test('omits absent cursor/parentId, keeps pageSize', () async {
      when(() => dio.get<Map<String, dynamic>>(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async =>
              _res({'items': [], 'nextCursor': null, 'hasMore': false}));

      await api.getCompanies(pageSize: 200);

      expect(capturedQuery(), {'pageSize': 200});
    });

    test('includes parentId + cursor when supplied', () async {
      when(() => dio.get<Map<String, dynamic>>(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async =>
              _res({'items': [], 'nextCursor': null, 'hasMore': false}));

      await api.getLocations(parentId: 'co1', cursor: 'abc', pageSize: 50);

      expect(capturedQuery(), {
        'parentId': 'co1',
        'cursor': 'abc',
        'pageSize': 50,
      });
    });

    test('empty-string cursor/parentId are omitted', () async {
      when(() => dio.get<Map<String, dynamic>>(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async =>
              _res({'items': [], 'nextCursor': null, 'hasMore': false}));

      await api.getBins(parentId: '', cursor: '');

      expect(capturedQuery(), isEmpty);
    });

    test('hits the correct path per level', () async {
      when(() => dio.get<Map<String, dynamic>>(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async =>
              _res({'items': [], 'nextCursor': null, 'hasMore': false}));

      await api.getWarehouses();

      verify(() => dio.get<Map<String, dynamic>>(
            '/master-data/warehouses',
            queryParameters: any(named: 'queryParameters'),
          )).called(1);
    });
  });

  group('MasterDataPage parsing', () {
    test('parses a non-empty page with a real cursor', () async {
      when(() => dio.get<Map<String, dynamic>>(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => _res({
                'items': [
                  {
                    'id': 'co1',
                    'name': 'Acme',
                    'isActive': true,
                    'createdAtUtc': '2026-01-01T00:00:00+00:00',
                    'updatedAtUtc': null,
                    'tenantId': 'tn1',
                  },
                ],
                'nextCursor': 'cursor-1',
                'hasMore': true,
              }));

      final page = await api.getCompanies();

      expect(page.items, hasLength(1));
      expect(page.items.single.id, 'co1');
      expect(page.items.single.tenantId, 'tn1');
      expect(page.nextCursor, 'cursor-1');
      expect(page.hasMore, isTrue);
    });

    test('parses an empty page — nextCursor null, hasMore false', () async {
      when(() => dio.get<Map<String, dynamic>>(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async =>
              _res({'items': [], 'nextCursor': null, 'hasMore': false}));

      final page = await api.getLocations();

      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
    });

    test('parses a bin with all denormalized ancestor ids', () async {
      when(() => dio.get<Map<String, dynamic>>(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => _res({
                'items': [
                  {
                    'id': 'b1',
                    'name': 'Bin 1',
                    'isActive': false,
                    'createdAtUtc': '2026-01-01T00:00:00+00:00',
                    'updatedAtUtc': '2026-02-01T00:00:00+00:00',
                    'tenantId': 'tn1',
                    'rackId': 'r1',
                    'warehouseId': 'w1',
                    'locationId': 'l1',
                    'companyId': 'co1',
                  },
                ],
                'nextCursor': 'c',
                'hasMore': false,
              }));

      final page = await api.getBins();
      final b = page.items.single;

      expect(b.rackId, 'r1');
      expect(b.warehouseId, 'w1');
      expect(b.locationId, 'l1');
      expect(b.companyId, 'co1');
      expect(b.isActive, isFalse);
      expect(b.updatedAtUtc, isNotNull);
    });
  });
}
