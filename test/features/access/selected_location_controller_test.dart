import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/access/data/selected_location_repository.dart';
import 'package:iams_mobile/features/access/presentation/controller/selected_location_controller.dart';
import 'package:iams_mobile/features/access/presentation/controller/selected_location_state.dart';

import '../../support/access_fixtures.dart';

/// The controller is the router's source of truth for the one-time location
/// gate: [SelectedLocationState.hasSelection] is what `redirectForAuth` reads.
void main() {
  late FakeSelectedLocationLocalDataSource store;
  late SelectedLocationController controller;

  setUp(() {
    store = FakeSelectedLocationLocalDataSource();
    controller = SelectedLocationController(SelectedLocationRepository(store));
  });

  tearDown(() => controller.close());

  test('starts unknown with no selection', () {
    expect(controller.state.status, SelectedLocationLoadStatus.unknown);
    expect(controller.state.hasSelection, isFalse);
  });

  test('load with an empty store → ready, still no selection (gate applies)',
      () async {
    await controller.load();

    expect(controller.state.status, SelectedLocationLoadStatus.ready);
    expect(controller.state.hasSelection, isFalse);
    expect(controller.state.locationId, isNull);
  });

  test('load restores a previously persisted selection', () async {
    store = FakeSelectedLocationLocalDataSource('loc-42');
    controller = SelectedLocationController(SelectedLocationRepository(store));

    await controller.load();

    expect(controller.state.hasSelection, isTrue);
    expect(controller.currentLocationId, 'loc-42');
  });

  test('select persists and flips hasSelection', () async {
    await controller.load();

    await controller.select('loc-7');

    expect(controller.state.hasSelection, isTrue);
    expect(controller.currentLocationId, 'loc-7');
    expect(store.value, 'loc-7'); // written through to storage
  });

  test('clear forgets the selection (re-arms the gate)', () async {
    await controller.select('loc-7');

    await controller.clear();

    expect(controller.state.status, SelectedLocationLoadStatus.ready);
    expect(controller.state.hasSelection, isFalse);
    expect(store.value, isNull);
  });
}
