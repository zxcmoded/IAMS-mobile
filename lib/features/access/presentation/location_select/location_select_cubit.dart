import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/models/scope.dart';
import '../../data/scope_repository.dart';

enum LocationSelectStatus { initial, loading, loaded, error }

/// State for the one-time "Select Current Location" gate. Loads the caller's
/// assigned locations from `GET /me/scope` (the same data [ScopeCubit] fetches)
/// and tracks the in-progress single-select choice.
class LocationSelectState extends Equatable {
  const LocationSelectState({
    this.status = LocationSelectStatus.initial,
    this.locations = const [],
    this.selectedId,
    this.errorCode,
    this.errorMessage,
  });

  final LocationSelectStatus status;
  final List<LocationRef> locations;
  final String? selectedId;
  final String? errorCode;
  final String? errorMessage;

  bool get hasLocations => locations.isNotEmpty;

  /// Continue is only enabled once a location is chosen.
  bool get canContinue => selectedId != null;

  LocationSelectState copyWith({
    LocationSelectStatus? status,
    List<LocationRef>? locations,
    String? selectedId,
    String? errorCode,
    String? errorMessage,
  }) =>
      LocationSelectState(
        status: status ?? this.status,
        locations: locations ?? this.locations,
        selectedId: selectedId ?? this.selectedId,
        errorCode: errorCode ?? this.errorCode,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  @override
  List<Object?> get props =>
      [status, locations, selectedId, errorCode, errorMessage];
}

class LocationSelectCubit extends Cubit<LocationSelectState> {
  LocationSelectCubit(this._scopeRepository)
      : super(const LocationSelectState());

  final ScopeRepository _scopeRepository;

  /// Shown when [load] fails with a connectivity error. Loading the assigned
  /// locations requires the network (scope has no offline cache) — mirrors
  /// [ScopeCubit]'s offline message verbatim.
  static const String _offlineMessage =
      "You're offline. Connect to the internet to choose your location.";

  /// Loads the caller's assigned locations. [preselectId] pre-selects the
  /// previously-chosen location when re-opened from the dashboard's "Change"
  /// action — but only if it is still in the assigned set.
  Future<void> load({String? preselectId}) async {
    emit(const LocationSelectState(status: LocationSelectStatus.loading));
    try {
      final scope = await _scopeRepository.loadScope();
      final locations = scope.assignedLocations;
      final stillAssigned =
          preselectId != null && locations.any((l) => l.id == preselectId);
      emit(LocationSelectState(
        status: LocationSelectStatus.loaded,
        locations: locations,
        selectedId: stillAssigned ? preselectId : null,
      ));
    } on ApiException catch (e) {
      emit(LocationSelectState(
        status: LocationSelectStatus.error,
        errorCode: e.code,
        errorMessage: e.isNetwork ? _offlineMessage : e.message,
      ));
    } catch (e, st) {
      // Catch-all so a non-[ApiException] failure never leaves the gate spinning
      // forever. Log the real cause; surface a generic, retryable message.
      developer.log(
        'LocationSelectCubit.load failed with a non-ApiException error',
        name: 'LocationSelectCubit',
        error: e,
        stackTrace: st,
        level: 1000, // SEVERE
      );
      emit(const LocationSelectState(
        status: LocationSelectStatus.error,
        errorCode: ApiErrorCode.unknown,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }

  /// Records the user's single-select choice (does not persist — persistence is
  /// the [SelectedLocationController]'s job on Continue).
  void choose(String locationId) => emit(state.copyWith(selectedId: locationId));

  Future<void> refresh() => load(preselectId: state.selectedId);
}
