import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/scanning/data/models/scan_result.dart';
import 'package:iams_mobile/features/scanning/data/scan_api.dart';
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
  late ScanApi api;

  setUp(() {
    dio = MockDio();
    api = ScanApi(dio);
  });

  Map<String, dynamic>? capturedBody() =>
      verify(() => dio.post<Map<String, dynamic>>(
            any(),
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>?;

  test('sends rawCode + deviceId; stamps rawCode onto the result', () async {
    when(() => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
        .thenAnswer((_) async => _res({
              'resolvedType': 'Sku',
              'resolvedEntityId': 'item-1',
              'label': 'Widget',
              'scanEventId': 'evt-1',
            }));

    final result =
        await api.resolve(rawCode: 'SKU-1', deviceId: 'dev', idempotencyKey: 'k');

    final body = capturedBody()!;
    expect(body['rawCode'], 'SKU-1');
    expect(body['deviceId'], 'dev');
    expect(body['idempotencyKey'], 'k');
    expect(result.resolvedType, ResolvedType.sku);
    expect(result.rawCode, 'SKU-1');
  });

  test('blocked result carries a null entity id (no leak)', () async {
    when(() => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
        .thenAnswer((_) async => _res({
              'resolvedType': 'Blocked',
              'resolvedEntityId': null,
              'label': null,
              'scanEventId': 'evt-2',
            }));

    final result = await api.resolve(rawCode: 'OTHER');

    expect(result.resolvedType, ResolvedType.blocked);
    expect(result.resolvedEntityId, isNull);
  });

  test('unknown resolvedType maps to ResolvedType.unknown (forward-compat)',
      () async {
    when(() => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
        .thenAnswer((_) async => _res({
              'resolvedType': 'SomethingNew',
              'scanEventId': 'evt-3',
            }));

    final result = await api.resolve(rawCode: 'X');
    expect(result.resolvedType, ResolvedType.unknown);
  });
}
