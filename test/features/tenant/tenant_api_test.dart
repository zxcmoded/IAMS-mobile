import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/tenant/data/models/access.dart';
import 'package:iams_mobile/features/tenant/data/models/enums.dart';
import 'package:iams_mobile/features/tenant/data/tenant_api.dart';
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
  late TenantApi api;

  setUp(() {
    dio = MockDio();
    api = TenantApi(dio);
  });

  group('getScope', () {
    test('decodes a successful response', () async {
      when(() => dio.get<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => _res({
          'user': {'id': 'u1', 'username': 'a', 'displayName': 'A'},
          'activeTenant': {'id': 't1', 'name': 'T', 'kind': 'Parent'},
          'activeCompany': {'id': 'c1', 'name': 'C', 'tenantId': 't1'},
          'activeLocation': null,
          'connections': [],
          'policyVersion': 0,
        }),
      );

      final scope = await api.getScope();

      expect(scope.activeCompany.id, 'c1');
      expect(scope.hasConnectedCompanies, isFalse);
    });

    // Regression test for the Companies-screen bug: a real Dio failure comes
    // back from `dio.get`/`dio.post` as a [DioException] whose `.error` field
    // carries the [ApiException] `ErrorInterceptor` already mapped — Dio's own
    // `assureDioException` returns an error unchanged when it is already a
    // `DioException`, so the interceptor re-emitting `err.copyWith(error:
    // mapped)` never changes what type is actually *thrown*. Before the
    // `unwrapApiErrors` fix, `TenantApi.getScope()` let that raw
    // [DioException] escape, so `ScopeCubit`'s `on ApiException catch` never
    // matched and every failure (including a plain offline error) fell
    // through to the generic "Something went wrong" catch-all instead of the
    // correct offline/error-specific message.
    test(
        'a DioException carrying a mapped ApiException surfaces as that '
        'ApiException, not the DioException', () async {
      const mapped = ApiException(
        code: ApiErrorCode.network,
        message: 'Network unavailable. Check your connection and retry.',
      );
      when(() => dio.get<Map<String, dynamic>>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/me/scope'),
          type: DioExceptionType.connectionError,
          error: mapped,
        ),
      );

      await expectLater(
        api.getScope(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.network)
              .having((e) => e.isNetwork, 'isNetwork', isTrue),
        ),
      );
    });

    test(
        'a DioException with no mapped ApiException falls back to a generic '
        'ApiException (defensive — ErrorInterceptor should always map first)',
        () async {
      when(() => dio.get<Map<String, dynamic>>(any())).thenThrow(
        DioException(requestOptions: RequestOptions(path: '/me/scope')),
      );

      await expectLater(
        api.getScope(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.unknown),
        ),
      );
    });
  });

  group('evaluate', () {
    test('surfaces the mapped ApiException on failure, not a DioException',
        () async {
      const mapped = ApiException(
        code: ApiErrorCode.accessDenied,
        message: 'You do not have access to any company.',
        statusCode: 403,
      );
      when(() => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/access/evaluate'),
          response: Response(
            requestOptions: RequestOptions(path: '/access/evaluate'),
            statusCode: 403,
          ),
          error: mapped,
        ),
      );

      final request = AccessRequest(
        resource: const ResourceRef(companyId: 'c2'),
        requiredPermission: PermissionLevel.read,
      );

      await expectLater(
        api.evaluate(request),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.accessDenied),
        ),
      );
    });
  });
}
