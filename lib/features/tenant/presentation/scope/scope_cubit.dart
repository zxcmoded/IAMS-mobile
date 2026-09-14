import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/models/scope.dart';
import '../../data/tenant_repository.dart';

enum ScopeStatus { initial, loading, loaded, error }

/// State for scope-driven screens (Company/Tenant Selector, Connection Scope).
/// Handles the explicit loading / error / empty (no-connected-company) states.
class ScopeState extends Equatable {
  const ScopeState({
    this.status = ScopeStatus.initial,
    this.scope,
    this.errorCode,
    this.errorMessage,
  });

  final ScopeStatus status;
  final Scope? scope;
  final String? errorCode;
  final String? errorMessage;

  bool get isLoading =>
      status == ScopeStatus.loading || status == ScopeStatus.initial;

  /// Empty state for the selector: signed in but no connected companies.
  bool get hasNoConnectedCompany =>
      status == ScopeStatus.loaded && scope != null && !scope!.hasConnectedCompanies;

  @override
  List<Object?> get props => [status, scope, errorCode, errorMessage];
}

class ScopeCubit extends Cubit<ScopeState> {
  ScopeCubit(this._repository) : super(const ScopeState());

  final TenantRepository _repository;

  Future<void> load() async {
    emit(const ScopeState(status: ScopeStatus.loading));
    try {
      final scope = await _repository.loadScope();
      emit(ScopeState(status: ScopeStatus.loaded, scope: scope));
    } on ApiException catch (e) {
      emit(ScopeState(
        status: ScopeStatus.error,
        errorCode: e.code,
        errorMessage: e.message,
      ));
    }
  }

  Future<void> refresh() => load();
}
