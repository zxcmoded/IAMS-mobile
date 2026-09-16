import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/models/access.dart';
import '../../data/tenant_repository.dart';

enum AccessStatus { initial, evaluating, loaded, error }

/// State for the Cross-Tenant Resource Access screen. `decision` drives the
/// allowed / read-only / access-denied UI states; `error` covers transport
/// failures (distinct from a well-formed Denied decision).
class AccessState extends Equatable {
  const AccessState({
    this.status = AccessStatus.initial,
    this.request,
    this.decision,
    this.errorCode,
    this.errorMessage,
  });

  final AccessStatus status;
  final AccessRequest? request;
  final AccessDecision? decision;
  final String? errorCode;
  final String? errorMessage;

  bool get isEvaluating => status == AccessStatus.evaluating;

  @override
  List<Object?> get props =>
      [status, request, decision, errorCode, errorMessage];
}

class AccessCubit extends Cubit<AccessState> {
  AccessCubit(this._repository) : super(const AccessState());

  final TenantRepository _repository;

  Future<void> evaluate(AccessRequest request) async {
    emit(AccessState(status: AccessStatus.evaluating, request: request));
    try {
      final decision = await _repository.evaluateAccess(request);
      emit(AccessState(
        status: AccessStatus.loaded,
        request: request,
        decision: decision,
      ));
    } on ApiException catch (e) {
      emit(AccessState(
        status: AccessStatus.error,
        request: request,
        errorCode: e.code,
        errorMessage: e.message,
      ));
    } catch (_) {
      // Catch-all for non-[ApiException] failures — e.g. a PlatformException
      // from secure storage or a TypeError/FormatException parsing an
      // unexpected response. Without this the Future error would go unhandled
      // and the cubit would stay in [AccessStatus.evaluating] forever (spinner
      // spins, no error shown). Surface a generic message rather than leaking
      // raw exception text to the UI.
      emit(AccessState(
        status: AccessStatus.error,
        request: request,
        errorCode: ApiErrorCode.unknown,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }
}
