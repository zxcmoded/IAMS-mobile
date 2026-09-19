import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/models/inventory_enums.dart';
import '../../data/models/inventory_item_detail.dart';
import '../../data/models/outbox_entry.dart';
import '../../data/inventory_repository.dart';
import '../../data/outbox_repository.dart';

/// One bin's on-hand as shown on item detail: the [observedQty] last confirmed
/// by the server, plus the net [pendingDelta] of not-yet-synced queued
/// mutations overlaid on top. [effectiveQty] is what the user sees. [version]
/// is null when the bin is known only from a pending mutation (never observed).
class BinStock extends Equatable {
  const BinStock({
    required this.binId,
    required this.observedQty,
    required this.pendingDelta,
    this.version,
  });

  final String binId;
  final double observedQty;
  final double pendingDelta;
  final int? version;

  double get effectiveQty => observedQty + pendingDelta;
  bool get hasPending => pendingDelta != 0;

  @override
  List<Object?> get props => [binId, observedQty, pendingDelta, version];
}

enum ItemDetailStatus { loading, loaded, notFound, error }

/// State for the F4 Item Detail screen. [detail] is the local-cache snapshot of
/// the item (its master fields + confirmed per-bin on-hand); it is null only in
/// the transient loading / notFound / error states. [bins] overlays this item's
/// pending-outbox deltas on top of the confirmed on-hand. [pending] lists this
/// item's queued/conflicted mutations for the inline "pending sync" section.
class InventoryItemState extends Equatable {
  const InventoryItemState({
    this.status = ItemDetailStatus.loading,
    this.detail,
    this.bins = const [],
    this.pending = const [],
    this.busyKey,
    this.errorCode,
    this.errorMessage,
  });

  final ItemDetailStatus status;
  final InventoryItemDetail? detail;
  final List<BinStock> bins;

  /// This item's outbox rows (most relevant first): anything not yet synced —
  /// pending, conflicted, or failed — so the user has an affordance to review.
  final List<OutboxEntry> pending;

  /// The idempotency key of a row currently being retried/discarded, for a
  /// per-row spinner.
  final String? busyKey;

  final String? errorCode;
  final String? errorMessage;

  bool get hasPending => pending.isNotEmpty;

  static const Object _unset = Object();

  InventoryItemState copyWith({
    ItemDetailStatus? status,
    Object? detail = _unset,
    List<BinStock>? bins,
    List<OutboxEntry>? pending,
    Object? busyKey = _unset,
    Object? errorCode = _unset,
    Object? errorMessage = _unset,
  }) =>
      InventoryItemState(
        status: status ?? this.status,
        detail: identical(detail, _unset)
            ? this.detail
            : detail as InventoryItemDetail?,
        bins: bins ?? this.bins,
        pending: pending ?? this.pending,
        busyKey: identical(busyKey, _unset) ? this.busyKey : busyKey as String?,
        errorCode:
            identical(errorCode, _unset) ? this.errorCode : errorCode as String?,
        errorMessage: identical(errorMessage, _unset)
            ? this.errorMessage
            : errorMessage as String?,
      );

  @override
  List<Object?> get props =>
      [status, detail, bins, pending, busyKey, errorCode, errorMessage];
}

class InventoryItemCubit extends Cubit<InventoryItemState> {
  InventoryItemCubit(this._repository, this._outbox, {required this.itemId})
      : super(const InventoryItemState());

  final InventoryRepository _repository;
  final OutboxRepository _outbox;
  final String itemId;

  /// Only pending + conflict rows overlay their delta (failed won't apply;
  /// synced is already folded into the observed on-hand).
  static bool _overlays(OutboxEntry e) =>
      e.status == OutboxStatus.pending || e.status == OutboxStatus.conflict;

  /// Reads the item **entirely from the local SQLite cache** — no API call.
  /// The confirmed per-bin on-hand comes from the cache; this item's pending
  /// outbox deltas are overlaid on top (so a just-queued mutation shows
  /// immediately). "Not found" now means "not in the local cache" (not a server
  /// 404) — i.e. not in the accessible/synced scope. Reading SQLite is
  /// effectively instant, so the transient `loading` state is barely visible.
  Future<void> load() async {
    emit(state.copyWith(
      status: ItemDetailStatus.loading,
      errorCode: null,
      errorMessage: null,
    ));
    try {
      final detail = await _repository.getItemDetail(itemId);
      final pending = await _outbox.outboxForItem(itemId);
      if (detail == null) {
        emit(state.copyWith(
          status: ItemDetailStatus.notFound,
          detail: null,
          bins: const [],
          pending: _unsynced(pending),
        ));
        return;
      }
      emit(state.copyWith(
        status: ItemDetailStatus.loaded,
        detail: detail,
        bins: _mergeFromDetail(detail, pending),
        pending: _unsynced(pending),
      ));
    } catch (_) {
      emit(state.copyWith(
        status: ItemDetailStatus.error,
        errorCode: ApiErrorCode.unknown,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }

  Future<void> refresh() => load();

  /// Retry a conflicted/failed row (rebased) then reload to reflect the outcome.
  Future<void> retry(String idempotencyKey) async {
    emit(state.copyWith(busyKey: idempotencyKey));
    try {
      await _outbox.retryEntry(idempotencyKey);
    } catch (_) {
      // Swallow — the reload surfaces the row's resulting state.
    }
    emit(state.copyWith(busyKey: null));
    await load();
  }

  Future<void> discard(String idempotencyKey) async {
    emit(state.copyWith(busyKey: idempotencyKey));
    await _outbox.discardEntry(idempotencyKey);
    emit(state.copyWith(busyKey: null));
    await load();
  }

  /// Push all pending mutations (e.g. user tapped "sync now" after reconnect),
  /// then reload.
  Future<void> syncNow() async {
    await _outbox.pushPending();
    await load();
  }

  // ---- Merge helpers --------------------------------------------------------

  List<OutboxEntry> _unsynced(List<OutboxEntry> all) => all
      .where((e) => e.status != OutboxStatus.synced)
      .toList(growable: false);

  Map<String, double> _pendingDeltas(List<OutboxEntry> pending) {
    final deltas = <String, double>{};
    for (final e in pending.where(_overlays)) {
      e.pendingBinDeltas().forEach((binId, delta) {
        deltas[binId] = (deltas[binId] ?? 0) + delta;
      });
    }
    return deltas;
  }

  List<BinStock> _mergeFromDetail(
    InventoryItemDetail detail,
    List<OutboxEntry> pending,
  ) {
    final deltas = _pendingDeltas(pending);
    final observed = {for (final b in detail.stockByBin) b.binId: b};
    return _combine(
      binIds: {...observed.keys, ...deltas.keys},
      observedQty: (id) => observed[id]?.quantityOnHand ?? 0,
      version: (id) => observed[id]?.version,
      deltas: deltas,
    );
  }

  List<BinStock> _combine({
    required Set<String> binIds,
    required double Function(String) observedQty,
    required int? Function(String) version,
    required Map<String, double> deltas,
  }) {
    final bins = binIds
        .map((id) => BinStock(
              binId: id,
              observedQty: observedQty(id),
              pendingDelta: deltas[id] ?? 0,
              version: version(id),
            ))
        .toList()
      ..sort((a, b) => a.binId.compareTo(b.binId));
    return bins;
  }
}
