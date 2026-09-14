import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'problem_details.dart';

/// Converts every [DioException] into a typed [ApiException] so higher layers
/// only ever catch one error type and always have a machine-readable `code`.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Already normalized (e.g. rethrown from the auth interceptor).
    if (err.error is ApiException) {
      handler.next(err);
      return;
    }

    final ApiException mapped;
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        mapped = const ApiException(
          code: ApiErrorCode.network,
          message: 'Network unavailable. Check your connection and retry.',
        );
        break;
      case DioExceptionType.badCertificate:
        mapped = const ApiException(
          code: ApiErrorCode.network,
          message: 'Secure connection failed.',
        );
        break;
      case DioExceptionType.cancel:
        mapped = const ApiException(
          code: ApiErrorCode.unknown,
          message: 'Request cancelled.',
        );
        break;
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        final response = err.response;
        if (response != null) {
          mapped = ProblemDetailsParser.parse(
            data: response.data,
            statusCode: response.statusCode,
          );
        } else {
          mapped = const ApiException(
            code: ApiErrorCode.network,
            message: 'Network unavailable. Check your connection and retry.',
          );
        }
        break;
    }

    handler.next(err.copyWith(error: mapped));
  }
}
