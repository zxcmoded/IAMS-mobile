import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/models/scope.dart';
import '../../data/scope_repository.dart';

enum ScopeStatus { initial, loading, loaded, error }

/// State for the Home screen — the caller's Company, role, and assigned
/// Locations from `GET /me/scope`. Handles the explicit loading / error states.
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

  @override
  List<Object?> get props => [status, scope, errorCode, errorMessage];
}

class ScopeCubit extends Cubit<ScopeState> {
  ScopeCubit(this._repository) : super(const ScopeState());

  /// Shown when [load] fails with a connectivity error. Scope has no offline
  /// cache, so this is a dead end until the device reconnects.
  static const String _offlineMessage =
      "You're offline. Connect to the internet to view your access.";

  final ScopeRepository _repository;

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
        // text. Scope is online-only (no local cache). Non-network
        // ApiExceptions keep their own [message].
        errorMessage: e.isNetwork ? _offlineMessage : e.message,
      ));
    } catch (e, st) {
      // Catch-all for non-[ApiException] failures — e.g. a PlatformException
      // from secure storage, a TypeError/FormatException parsing an unexpected
      // response, or a raw [DioException] escaping the data layer. Without this
      // the Future error would go unhandled and the cubit would stay in
      // [ScopeStatus.loading] forever (spinner spins, no error shown). Surface
      // a generic message rather than leaking raw exception text to the UI, but
      // log the real exception+stack so a swallowed failure is never invisible.
      developer.log(
        'ScopeCubit.load failed with a non-ApiException error',
        name: 'ScopeCubit',
        error: e,
        stackTrace: st,
        level: 1000, // SEVERE
      );
      emit(const ScopeState(
        status: ScopeStatus.error,
        errorCode: ApiErrorCode.unknown,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }

  Future<void> refresh() => load();
}
