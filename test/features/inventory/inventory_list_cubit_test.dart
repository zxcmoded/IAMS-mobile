import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/inventory/data/inventory_api.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_item.dart';
import 'package:iams_mobile/features/inventory/presentation/list/inventory_list_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockInventoryApi extends Mock implements InventoryApi {}

InventoryItem _item(String id, {double qty = 5}) =>
    InventoryItem(id: id, sku: id, name: 'Item $id', isActive: true, totalQuantityOnHand: qty);

InventoryPage _page(List<InventoryItem> items,
        {int page = 1, bool hasMore = false}) =>
    InventoryPage(items: items, page: page, pageSize: 50, hasMore: hasMore);

void main() {
  setUpAll(() => registerFallbackValue(InventoryFilter.all));

  late MockInventoryApi api;
  late InventoryListCubit cubit;

  setUp(() {
    api = MockInventoryApi();
    cubit = InventoryListCubit(api);
  });

  tearDown(() => cubit.close());

  test('load populates items', () async {
    when(() => api.listItems(
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => _page([_item('a'), _item('b')]));

    await cubit.load();

    expect(cubit.state.status, InventoryListStatus.loaded);
    expect(cubit.state.items, hasLength(2));
    expect(cubit.state.isEmpty, isFalse);
  });

  test('empty result is the distinct empty state', () async {
    when(() => api.listItems(
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => _page(const []));

    await cubit.load();

    expect(cubit.state.isEmpty, isTrue);
  });

  test('setFilter reloads with the new filter', () async {
    when(() => api.listItems(
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => _page([_item('a')]));

    await cubit.setFilter(InventoryFilter.lowStock);

    expect(cubit.state.filter, InventoryFilter.lowStock);
    verify(() => api.listItems(
        search: any(named: 'search'),
        filter: InventoryFilter.lowStock,
        page: 1,
        pageSize: any(named: 'pageSize'))).called(1);
  });

  test('loadMore appends the next page', () async {
    when(() => api.listItems(
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: 1,
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => _page([_item('a')], hasMore: true));
    when(() => api.listItems(
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: 2,
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => _page([_item('b')], page: 2));

    await cubit.load();
    await cubit.loadMore();

    expect(cubit.state.items.map((i) => i.id).toList(), ['a', 'b']);
    expect(cubit.state.hasMore, isFalse);
  });

  test('error surfaces a retryable error state', () async {
    when(() => api.listItems(
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize')))
        .thenThrow(const ApiException(
            code: ApiErrorCode.network, message: 'offline'));

    await cubit.load();

    expect(cubit.state.status, InventoryListStatus.error);
    expect(cubit.state.errorCode, ApiErrorCode.network);
  });
}
