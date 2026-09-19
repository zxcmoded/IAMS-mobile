import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/inventory/data/inventory_api.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart'
    show TransactionType, StockCountStatus;
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

  Map<String, dynamic>? capturedBody() =>
      verify(() => dio.post<Map<String, dynamic>>(
            any(),
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>?;

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
}
