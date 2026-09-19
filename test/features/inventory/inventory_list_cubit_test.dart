import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/inventory/data/inventory_repository.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_item.dart';
import 'package:iams_mobile/features/inventory/presentation/list/inventory_list_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockInventoryRepository extends Mock implements InventoryRepository {}

InventoryItem _item(String id, {double qty = 5}) => InventoryItem(
    id: id, sku: id, name: 'Item $id', isActive: true, totalQuantityOnHand: qty);

InventoryPage _page(List<InventoryItem> items,
        {int page = 1, bool hasMore = false}) =>
    InventoryPage(items: items, page: page, pageSize: 50, hasMore: hasMore);

void main() {
  setUpAll(() => registerFallbackValue(InventoryFilter.all));

  late MockInventoryRepository repo;
  late InventoryListCubit cubit;

  setUp(() {
    repo = MockInventoryRepository();
    cubit = InventoryListCubit(repo);
  });

  tearDown(() => cubit.close());

  test('load reads the local repository (no API) and populates items', () async {
    when(() => repo.getList(
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
    when(() => repo.getList(
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => _page(const []));

    await cubit.load();

    expect(cubit.state.isEmpty, isTrue);
  });

  test('setFilter reloads with the new filter', () async {
    when(() => repo.getList(
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => _page([_item('a')]));

    await cubit.setFilter(InventoryFilter.lowStock);

    expect(cubit.state.filter, InventoryFilter.lowStock);
    verify(() => repo.getList(
        search: any(named: 'search'),
        filter: InventoryFilter.lowStock,
        page: 1,
        pageSize: any(named: 'pageSize'))).called(1);
  });

  test('loadMore appends the next local page', () async {
    when(() => repo.getList(
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: 1,
            pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => _page([_item('a')], hasMore: true));
    when(() => repo.getList(
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

  test('a local read failure surfaces a retryable error state', () async {
    when(() => repo.getList(
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize')))
        .thenThrow(Exception('sqlite boom'));

    await cubit.load();

    expect(cubit.state.status, InventoryListStatus.error);
  });
}
