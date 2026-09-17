import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/inventory_api.dart';
import '../../data/models/inventory_enums.dart';
import '../../data/models/inventory_item.dart';

enum InventoryListStatus { initial, loading, loaded, error }

/// State for the F4 inventory list. [items] is the accumulated set across
/// loaded pages; an empty [items] in [InventoryListStatus.loaded] is the
/// (distinct) empty state. Low/zero-stock flagging is derived per-row in the
/// UI from `totalQuantityOnHand`.
class InventoryListState extends Equatable {
  const InventoryListState({
    this.status = InventoryListStatus.initial,
    this.items = const [],
    this.filter = InventoryFilter.all,
    this.search = '',
    this.page = 1,
    this.hasMore = false,
    this.loadingMore = false,
    this.errorCode,
    this.errorMessage,
  });

  final InventoryListStatus status;
  final List<InventoryItem> items;
  final InventoryFilter filter;
  final String search;
  final int page;
  final bool hasMore;
  final bool loadingMore;
  final String? errorCode;
  final String? errorMessage;

  bool get isEmpty =>
      status == InventoryListStatus.loaded && items.isEmpty;

  static const Object _unset = Object();

  InventoryListState copyWith({
    InventoryListStatus? status,
    List<InventoryItem>? items,
    InventoryFilter? filter,
    String? search,
    int? page,
    bool? hasMore,
    bool? loadingMore,
    Object? errorCode = _unset,
    Object? errorMessage = _unset,
  }) =>
      InventoryListState(
        status: status ?? this.status,
        items: items ?? this.items,
        filter: filter ?? this.filter,
        search: search ?? this.search,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        errorCode:
            identical(errorCode, _unset) ? this.errorCode : errorCode as String?,
        errorMessage: identical(errorMessage, _unset)
            ? this.errorMessage
            : errorMessage as String?,
      );

  @override
  List<Object?> get props => [
        status,
        items,
        filter,
        search,
        page,
        hasMore,
        loadingMore,
        errorCode,
        errorMessage,
      ];
}

/// Drives the inventory list. The list itself is an **online** view (the
/// contract's offset-paginated search), so a load failure surfaces a retryable
/// error rather than silently showing stale data.
class InventoryListCubit extends Cubit<InventoryListState> {
  InventoryListCubit(this._api) : super(const InventoryListState());

  final InventoryApi _api;

  static const int _pageSize = 50;

  Future<void> load() => _loadFirstPage(
        filter: state.filter,
        search: state.search,
      );

  Future<void> refresh() => load();

  Future<void> setFilter(InventoryFilter filter) {
    if (filter == state.filter && state.status == InventoryListStatus.loaded) {
      return Future.value();
    }
    return _loadFirstPage(filter: filter, search: state.search);
  }

  Future<void> setSearch(String search) =>
      _loadFirstPage(filter: state.filter, search: search.trim());

  Future<void> _loadFirstPage({
    required InventoryFilter filter,
    required String search,
  }) async {
    emit(state.copyWith(
      status: InventoryListStatus.loading,
      filter: filter,
      search: search,
      page: 1,
      errorCode: null,
      errorMessage: null,
    ));
    try {
      final page = await _api.listItems(
        search: search.isEmpty ? null : search,
        filter: filter,
        page: 1,
        pageSize: _pageSize,
      );
      emit(state.copyWith(
        status: InventoryListStatus.loaded,
        items: page.items,
        page: page.page,
        hasMore: page.hasMore,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(
        status: InventoryListStatus.error,
        errorCode: e.code,
        errorMessage: e.message,
      ));
    } catch (_) {
      emit(state.copyWith(
        status: InventoryListStatus.error,
        errorCode: ApiErrorCode.unknown,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore ||
        state.loadingMore ||
        state.status != InventoryListStatus.loaded) {
      return;
    }
    emit(state.copyWith(loadingMore: true));
    try {
      final next = state.page + 1;
      final page = await _api.listItems(
        search: state.search.isEmpty ? null : state.search,
        filter: state.filter,
        page: next,
        pageSize: _pageSize,
      );
      emit(state.copyWith(
        items: [...state.items, ...page.items],
        page: page.page,
        hasMore: page.hasMore,
        loadingMore: false,
      ));
    } on ApiException catch (e) {
      // A page-append failure keeps the already-loaded list; surface the code
      // without dropping to the full-screen error state.
      emit(state.copyWith(
        loadingMore: false,
        errorCode: e.code,
        errorMessage: e.message,
      ));
    } catch (_) {
      emit(state.copyWith(loadingMore: false, errorCode: ApiErrorCode.unknown));
    }
  }
}
