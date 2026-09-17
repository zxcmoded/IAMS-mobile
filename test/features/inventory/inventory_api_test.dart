import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/inventory/data/inventory_api.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
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
  late InventoryApi api;

  setUp(() {
    dio = MockDio();
    api = InventoryApi(dio);
  });

  Map<String, dynamic>? capturedQuery() =>
      verify(() => dio.get<Map<String, dynamic>>(
            any(),
            queryParameters: captureAny(named: 'queryParameters'),
          )).captured.single as Map<String, dynamic>?;

  Map<String, dynamic>? capturedBody() =>
      verify(() => dio.post<Map<String, dynamic>>(
            any(),
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>?;

  group('listItems query', () {
    test('omits filter when `all`, keeps page/pageSize', () async {
      when(() => dio.get<Map<String, dynamic>>(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async =>
              _res({'items': [], 'page': 1, 'pageSize': 50, 'hasMore': false}));

      await api.listItems();

      expect(capturedQuery(), {'page': 1, 'pageSize': 50});
    });

    test('includes search + filter token when set', () async {
      when(() => dio.get<Map<String, dynamic>>(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async =>
              _res({'items': [], 'page': 1, 'pageSize': 50, 'hasMore': false}));

      await api.listItems(search: 'wid', filter: InventoryFilter.lowStock);

      expect(capturedQuery(), {
        'search': 'wid',
        'filter': 'low_stock',
        'page': 1,
        'pageSize': 50,
      });
    });
  });

  group('mutation bodies', () {
    test('receive includes base version only when provided', () async {
      when(() => dio.post<Map<String, dynamic>>(any(),
              data: any(named: 'data')))
          .thenAnswer((_) async => _res({
                'transactionId': 't',
                'transactionType': 'Receive',
                'status': 'Applied',
                'quantity': 10,
                'stockLevels': [],
                'replayed': false,
              }));

      await api.receive(
        idempotencyKey: 'k',
        inventoryItemId: 'i',
        destinationBinId: 'b',
        quantity: 10,
        baseDestinationStockVersion: 3,
      );

      final body = capturedBody()!;
      expect(body['idempotencyKey'], 'k');
      expect(body['baseDestinationStockVersion'], 3);
    });

    test('receive omits base version when null', () async {
      when(() => dio.post<Map<String, dynamic>>(any(),
              data: any(named: 'data')))
          .thenAnswer((_) async => _res({
                'transactionId': 't',
                'transactionType': 'Receive',
                'status': 'Applied',
                'quantity': 10,
                'stockLevels': [],
                'replayed': false,
              }));

      await api.receive(
          idempotencyKey: 'k',
          inventoryItemId: 'i',
          destinationBinId: 'b',
          quantity: 10);

      expect(capturedBody()!.containsKey('baseDestinationStockVersion'), isFalse);
    });

    test('parses a movement response with stock levels', () async {
      when(() => dio.post<Map<String, dynamic>>(any(),
              data: any(named: 'data')))
          .thenAnswer((_) async => _res({
                'transactionId': 't1',
                'transactionType': 'Transfer',
                'status': 'Applied',
                'quantity': 4,
                'stockLevels': [
                  {'binId': 'b1', 'quantityOnHand': 6, 'version': 4},
                  {'binId': 'b2', 'quantityOnHand': 4, 'version': 2},
                ],
                'replayed': false,
              }));

      final resp = await api.transfer(
          idempotencyKey: 'k',
          inventoryItemId: 'i',
          sourceBinId: 'b1',
          destinationBinId: 'b2',
          quantity: 4);

      expect(resp.stockLevels, hasLength(2));
      expect(resp.stockLevels.first.version, 4);
      expect(resp.transactionType, TransactionType.transfer);
    });

    test('parses a count response (PendingApproval)', () async {
      when(() => dio.post<Map<String, dynamic>>(any(),
              data: any(named: 'data')))
          .thenAnswer((_) async => _res({
                'id': 'c1',
                'status': 'PendingApproval',
                'countedQuantity': 50,
                'systemQuantity': 10,
                'variance': 40,
                'varianceThreshold': 5,
                'varianceThresholdType': 'AbsoluteQuantity',
                'stockVersion': 7,
                'replayed': false,
              }));

      final resp = await api.count(
          idempotencyKey: 'k',
          inventoryItemId: 'i',
          binId: 'b',
          countedQuantity: 50);

      expect(resp.status, StockCountStatus.pendingApproval);
      expect(resp.variance, 40);
    });
  });

  test('getItem hits the by-id path', () async {
    when(() => dio.get<Map<String, dynamic>>(any())).thenAnswer((_) async =>
        _res({
          'id': 'i1',
          'sku': 'S',
          'name': 'N',
          'isActive': true,
          'totalQuantityOnHand': 3,
          'stockByBin': [],
          'movements': [],
        }));

    final detail = await api.getItem('i1');

    expect(detail.id, 'i1');
    verify(() => dio.get<Map<String, dynamic>>('/inventory/items/i1')).called(1);
  });
}
