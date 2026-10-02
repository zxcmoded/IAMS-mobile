import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/core/navigation/nav_bar_reserved_space.dart';
import 'package:iams_mobile/features/inventory/data/inventory_repository.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_item.dart';
import 'package:iams_mobile/features/inventory/presentation/list/inventory_list_cubit.dart';
import 'package:iams_mobile/features/inventory/presentation/list/inventory_list_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockInventoryRepository extends Mock implements InventoryRepository {}

/// Regression coverage for the "Create Inventory" FAB rendering hidden
/// behind MainShell's floating pill bottom nav bar (see main_shell.dart /
/// NavBarReservedSpace). InventoryListScreen doesn't know about MainShell
/// directly — it only reads whatever NavBarReservedSpace.of(context)
/// publishes — so these tests drive that InheritedWidget directly rather
/// than pumping the whole shell + router.
void main() {
  setUpAll(() => registerFallbackValue(InventoryFilter.all));

  late MockInventoryRepository repo;

  setUp(() {
    repo = MockInventoryRepository();
    when(() => repo.getList(
          search: any(named: 'search'),
          filter: any(named: 'filter'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).thenAnswer((_) async =>
        const InventoryPage(items: [], page: 1, pageSize: 50, hasMore: false));

    sl.registerFactory<InventoryListCubit>(() => InventoryListCubit(repo));
  });

  tearDown(() => sl.reset());

  Future<void> pumpScreen(WidgetTester tester, {required double reservedHeight}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NavBarReservedSpace(
          height: reservedHeight,
          child: const InventoryListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the Create Inventory FAB', (tester) async {
    await pumpScreen(tester, reservedHeight: 0);

    expect(find.byKey(const Key('create_inventory')), findsOneWidget);
  });

  testWidgets(
      'FAB rests above the band MainShell reserves for its floating nav '
      'bar, not overlapped by it', (tester) async {
    // Mirrors the footprint MainShell.build computes for its
    // _ArtisticNavBar: device bottom safe-area inset + the pill's own
    // bottom gap + its height.
    const bottomInset = 34.0;
    const reservedHeight = bottomInset + 12 + 64;
    await pumpScreen(tester, reservedHeight: reservedHeight);

    final fabBottom =
        tester.getRect(find.byKey(const Key('create_inventory'))).bottom;
    final screenHeight = tester.getRect(find.byType(MaterialApp)).height;

    // The reserved band is the bottom `reservedHeight` px of the screen —
    // the FAB must sit entirely above it, never dipping in.
    final bandTop = screenHeight - reservedHeight;
    expect(fabBottom, lessThanOrEqualTo(bandTop));
  });
}
