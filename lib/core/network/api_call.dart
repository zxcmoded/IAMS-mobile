import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Runs a Dio [request] and re-throws any failure as the flat [ApiException]
/// the rest of the app is written to expect.
///
/// [ErrorInterceptor] normalizes every failure into a typed [ApiException],
/// but Dio's own contract is that a failed request always completes with a
/// [DioException] — the mapped [ApiException] only ever reaches
/// [DioException.error]. `DioMixin.assureDioException` (see the `dio`
/// package) returns an error unchanged when it is already a [DioException],
/// so re-emitting `err.copyWith(error: mapped)` from the interceptor's
/// `onError` does not change the exception *type* Dio ultimately throws from
/// `dio.get/post/...`. Without this unwrap, every `on ApiException catch`
/// clause in a cubit/repository silently never matches a real network
/// failure — including a plain offline/connection error — and it falls
/// through to that call site's generic catch-all instead (e.g. the Companies
/// screen always showing "Something went wrong" instead of "You're
/// offline..."). Every `*Api` class should route its Dio calls through this
/// so `ApiException` is genuinely the only error type higher layers ever see.
Future<T> unwrapApiErrors<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on DioException catch (e) {
    final mapped = e.error;
    if (mapped is ApiException) {
      throw mapped;
    }
    // Defensive fallback — should not happen, since ErrorInterceptor maps
    // every DioException it sees, but never let a raw DioException escape
    // the data layer.
    throw const ApiException(
      code: ApiErrorCode.unknown,
      message: 'Something went wrong. Please try again.',
    );
  }
}
