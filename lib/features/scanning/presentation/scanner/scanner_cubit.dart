import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/models/scan_result.dart';
import '../../data/scan_repository.dart';

/// State for the F3 Scanner screen. The visible banner is derived from
/// [lastResult] + [resolving] + [cameraPermissionDenied] rather than a single
/// phase enum, so a batch-mode scan can keep the viewport live while showing
/// the previous outcome. [history] backs the "last scanned" affordance
/// (most-recent-first, capped).
class ScannerState extends Equatable {
  const ScannerState({
    this.cameraPermissionDenied = false,
    this.flashOn = false,
    this.batchMode = false,
    this.resolving = false,
    this.lastResult,
    this.history = const [],
    this.errorCode,
    this.errorMessage,
  });

  final bool cameraPermissionDenied;
  final bool flashOn;
  final bool batchMode;
  final bool resolving;

  /// Most recent resolve outcome of *any* type (sku/location/asset/no-match/
  /// blocked). Null before the first scan.
  final ScanResult? lastResult;

  /// Batch-mode scan history, most-recent-first, capped at [_historyCap].
  final List<ScanResult> history;

  final String? errorCode;
  final String? errorMessage;

  bool get hasError => errorCode != null;

  /// Sentinel distinguishing "argument omitted" (preserve) from an explicit
  /// `null` (clear) — the Phase 1 cubit convention.
  static const Object _unset = Object();

  ScannerState copyWith({
    bool? cameraPermissionDenied,
    bool? flashOn,
    bool? batchMode,
    bool? resolving,
    Object? lastResult = _unset,
    List<ScanResult>? history,
    Object? errorCode = _unset,
    Object? errorMessage = _unset,
  }) =>
      ScannerState(
        cameraPermissionDenied:
            cameraPermissionDenied ?? this.cameraPermissionDenied,
        flashOn: flashOn ?? this.flashOn,
        batchMode: batchMode ?? this.batchMode,
        resolving: resolving ?? this.resolving,
        lastResult: identical(lastResult, _unset)
            ? this.lastResult
            : lastResult as ScanResult?,
        history: history ?? this.history,
        errorCode:
            identical(errorCode, _unset) ? this.errorCode : errorCode as String?,
        errorMessage: identical(errorMessage, _unset)
            ? this.errorMessage
            : errorMessage as String?,
      );

  @override
  List<Object?> get props => [
        cameraPermissionDenied,
        flashOn,
        batchMode,
        resolving,
        lastResult,
        history,
        errorCode,
        errorMessage,
      ];
}

/// Drives the Scanner screen. Owns the flash/batch toggles, the camera
/// permission state, and — critically — the guards that stop a single physical
/// scan from firing multiple resolve calls:
///
/// 1. **In-flight guard** ([resolving]): while a resolve is outstanding, further
///    camera detections are dropped. A camera streams many frames per second
///    for one barcode; without this each frame would POST `/scan/resolve`.
/// 2. **Rapid-duplicate guard** ([_dedupeWindow]): in batch mode, the same code
///    scanned again within the window is ignored, so lingering on one label
///    doesn't re-resolve it. Manual entry bypasses this (it's deliberate).
class ScannerCubit extends Cubit<ScannerState> {
  ScannerCubit(this._repository) : super(const ScannerState());

  final ScanRepository _repository;

  static const int _historyCap = 20;
  static const Duration _dedupeWindow = Duration(seconds: 3);

  String? _lastAcceptedCode;
  DateTime? _lastAcceptedAt;

  void toggleFlash() => emit(state.copyWith(flashOn: !state.flashOn));

  void toggleBatch() => emit(state.copyWith(batchMode: !state.batchMode));

  /// Set when the camera plugin reports the OS camera permission was denied —
  /// the screen then shows the permission-denied state with the manual-entry
  /// fallback foregrounded.
  void setCameraPermissionDenied(bool denied) =>
      emit(state.copyWith(cameraPermissionDenied: denied));

  /// A code detected by the camera. Subject to both the in-flight and the
  /// rapid-duplicate guards.
  Future<void> onScanned(String rawCode) => _resolve(rawCode, dedupe: true);

  /// A code typed via the manual-entry fallback. Subject only to the in-flight
  /// guard — re-typing the same code is always honoured.
  Future<void> submitManual(String rawCode) =>
      _resolve(rawCode, dedupe: false);

  Future<void> _resolve(String rawCode, {required bool dedupe}) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;

    // In-flight guard: never let a second resolve start while one is running.
    if (state.resolving) return;

    // Rapid-duplicate guard (batch/camera only).
    if (dedupe && state.batchMode && _isRapidDuplicate(code)) return;

    emit(state.copyWith(resolving: true, errorCode: null, errorMessage: null));
    try {
      final result = await _repository.resolve(code);
      _lastAcceptedCode = code;
      _lastAcceptedAt = DateTime.now();
      emit(state.copyWith(
        resolving: false,
        lastResult: result,
        history: _pushHistory(result),
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(
        resolving: false,
        errorCode: e.code,
        errorMessage: e.message,
      ));
    } catch (_) {
      // Non-[ApiException] failure (e.g. secure-storage read for the device id,
      // or an unexpected parse). Surface a generic message rather than leaving
      // [resolving] stuck true.
      emit(state.copyWith(
        resolving: false,
        errorCode: ApiErrorCode.unknown,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }

  bool _isRapidDuplicate(String code) {
    final at = _lastAcceptedAt;
    return code == _lastAcceptedCode &&
        at != null &&
        DateTime.now().difference(at) < _dedupeWindow;
  }

  List<ScanResult> _pushHistory(ScanResult result) {
    if (!state.batchMode) return state.history;
    return [result, ...state.history].take(_historyCap).toList(growable: false);
  }

  /// Clears a consumed error so the viewport returns to the plain scanning
  /// state (e.g. after the user dismisses a transient network error).
  void clearError() =>
      emit(state.copyWith(errorCode: null, errorMessage: null));
}
