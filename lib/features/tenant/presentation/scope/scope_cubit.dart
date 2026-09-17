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

  /// Shown when [loadScope] fails with a connectivity error. Scope has no
  /// offline cache, so this is a dead end until the device reconnects.
  static const String _offlineMessage =
      "You're offline. Connect to the internet to view your companies.";

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
        // A plain connectivity failure is surfaced with a distinct, explicit
        // "you're offline" message rather than the generic server-supplied
        // text. Scope is online-only (no local cache), so the user genuinely
        // cannot pick/switch companies while offline — the copy makes that
        // clear instead of reading as an ambiguous failure. Non-network
        // ApiExceptions keep their own [message].
        errorMessage: e.isNetwork ? _offlineMessage : e.message,
      ));
    } catch (_) {
      // Catch-all for non-[ApiException] failures — e.g. a PlatformException
      // from secure storage or a TypeError/FormatException parsing an
      // unexpected response. Without this the Future error would go unhandled
      // and the cubit would stay in [ScopeStatus.loading] forever (spinner
      // spins, no error shown). Surface a generic message rather than leaking
      // raw exception text to the UI.
      emit(const ScopeState(
        status: ScopeStatus.error,
        errorCode: ApiErrorCode.unknown,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }

  Future<void> refresh() => load();
}
