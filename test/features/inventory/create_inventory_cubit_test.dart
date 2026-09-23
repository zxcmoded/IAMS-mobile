import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/access/presentation/controller/selected_location_controller.dart';
import 'package:iams_mobile/features/inventory/data/inventory_record_repository.dart';
import 'package:iams_mobile/features/inventory/data/inventory_repository.dart';
import 'package:iams_mobile/features/inventory/presentation/create/create_inventory_cubit.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_repository.dart';

import '../../support/access_fixtures.dart';
import '../../support/inventory_fixtures.dart';
import '../../support/masterdata_fixtures.dart';

/// The Create-Inventory flow is offline-first: warehouse/rack/bin/SKU validation
/// all read local SQLite (no API), records are saved locally and always stamped
/// `isOffline = true`. These tests drive the cubit through fakes only.
void main() {
  late FakeHierarchyLocalDataSource hierarchyLocal;
  late FakeInventoryLocalDataSource invLocal;
  late FakeOutboxLocalDataSource outbox;
  late FakeInventoryRecordLocalDataSource recordLocal;
  late HierarchyRepository hierarchy;
  late InventoryRepository inventory;
  late InventoryRecordRepository records;
  late SelectedLocationController selectedLocation;

  // A controllable clock for the scan double-fire guard.
  late DateTime now;

  setUp(() async {
    hierarchyLocal = FakeHierarchyLocalDataSource();
    invLocal = FakeInventoryLocalDataSource();
    outbox = FakeOutboxLocalDataSource();
    recordLocal = FakeInventoryRecordLocalDataSource();
    hierarchy = HierarchyRepository(hierarchyLocal);
    inventory = InventoryRepository(invLocal, outbox);
    records = InventoryRecordRepository(recordLocal);
    selectedLocation = buildSelectedLocationController();
    await selectedLocation.select('l1'); // current location
    now = DateTime.utc(2026, 1, 1);
  });

  CreateInventoryCubit build() => CreateInventoryCubit(
        hierarchy: hierarchy,
        inventory: inventory,
        records: records,
        selectedLocation: selectedLocation,
        clock: () => now,
      );

  // A warehouse 'WH001' in the current location l1 (with a rack + bin), plus a
  // warehouse 'WH999' in a *different* location l2 to test scope rejection.
  void seedHierarchy() {
    hierarchyLocal.seedRow(
        'warehouse', warehouse('w1', locationId: 'l1', name: 'WH001').toRow());
    hierarchyLocal.seedRow(
        'warehouse', warehouse('w9', locationId: 'l2', name: 'WH999').toRow());
    hierarchyLocal.seedRow('rack',
        rack('r1', warehouseId: 'w1', locationId: 'l1', name: 'RACK001').toRow());
    hierarchyLocal.seedRow(
        'bin',
        bin('b1', rackId: 'r1', warehouseId: 'w1', locationId: 'l1', name: 'BIN001')
            .toRow());
  }

  void seedItems() {
    invLocal.seedItem(itemSync('i1', sku: 'SKU001', name: 'Widget', barcode: 'BAR001'));
    invLocal.seedItem(itemSync('i2', sku: 'SKU002', name: 'Gadget'));
  }

  group('warehouse validation', () {
    test('accepts a warehouse in the current location and loads its racks',
        () async {
      seedHierarchy();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.validateWarehouse('WH001');

      expect(cubit.state.warehouse?.id, 'w1');
      expect(cubit.state.warehouseError, isNull);
      expect(cubit.state.racks.map((r) => r.id), ['r1']);
    });

    test('is case-insensitive', () async {
      seedHierarchy();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.validateWarehouse('wh001');

      expect(cubit.state.warehouse?.id, 'w1');
    });

    test('rejects a warehouse not covered by the current location', () async {
      seedHierarchy();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.validateWarehouse('WH999'); // exists, but under l2

      expect(cubit.state.warehouse, isNull);
      expect(cubit.state.warehouseError, isNotNull);
      expect(cubit.state.racks, isEmpty);
    });

    test('re-entering an invalid code clears a previously valid warehouse',
        () async {
      seedHierarchy();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.validateWarehouse('WH001');
      expect(cubit.state.warehouse?.id, 'w1');

      await cubit.validateWarehouse('NOPE');
      expect(cubit.state.warehouse, isNull);
      expect(cubit.state.racks, isEmpty);
    });
  });

  group('rack/bin cascade', () {
    test('selecting a rack loads only its bins; clearing it resets the bin',
        () async {
      seedHierarchy();
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.validateWarehouse('WH001');

      await cubit.selectRack('r1');
      expect(cubit.state.selectedRackId, 'r1');
      expect(cubit.state.bins.map((b) => b.id), ['b1']);

      cubit.selectBin('b1');
      expect(cubit.state.selectedBinId, 'b1');

      await cubit.selectRack(null);
      expect(cubit.state.selectedRackId, isNull);
      expect(cubit.state.bins, isEmpty);
      expect(cubit.state.selectedBinId, isNull);
    });

    test('changing rack resets the previously selected bin', () async {
      seedHierarchy();
      hierarchyLocal.seedRow('rack',
          rack('r2', warehouseId: 'w1', locationId: 'l1', name: 'RACK002').toRow());
      hierarchyLocal.seedRow(
          'bin',
          bin('b2', rackId: 'r2', warehouseId: 'w1', locationId: 'l1', name: 'BIN002')
              .toRow());
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.validateWarehouse('WH001');

      await cubit.selectRack('r1');
      cubit.selectBin('b1');
      await cubit.selectRack('r2');

      expect(cubit.state.selectedBinId, isNull);
      expect(cubit.state.bins.map((b) => b.id), ['b2']);
    });
  });

  group('SKU scan / accumulate', () {
    test('an unknown SKU is rejected and adds no line', () async {
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.scanSku('NOPE');

      expect(cubit.state.lines, isEmpty);
      expect(cubit.state.skuError, isNotNull);
    });

    test('resolves by sku and by barcode', () async {
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.scanSku('SKU001');
      now = now.add(const Duration(seconds: 1));
      await cubit.scanSku('BAR001'); // same item via barcode

      // Both resolve to i1 → one accumulated line, not two.
      expect(cubit.state.lines.single.inventoryItemId, 'i1');
      expect(cubit.state.lines.single.quantity, 2);
    });

    test('repeated scans of the same SKU accumulate onto one line', () async {
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);

      // Three deliberate scans at 0.5s intervals — all accepted.
      await cubit.scanSku('SKU001');
      now = now.add(const Duration(milliseconds: 500));
      await cubit.scanSku('SKU001');
      now = now.add(const Duration(milliseconds: 500));
      await cubit.scanSku('SKU001');

      expect(cubit.state.lines.length, 1);
      expect(cubit.state.lines.single.quantity, 3);
    });

    test('a double-fire within the guard window is ignored', () async {
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.scanSku('SKU001'); // t=0 accepted
      now = now.add(const Duration(milliseconds: 100));
      await cubit.scanSku('SKU001'); // +100ms → double-fire, ignored
      now = now.add(const Duration(milliseconds: 100));
      await cubit.scanSku('SKU001'); // +100ms from last fire → still ignored

      expect(cubit.state.lines.single.quantity, 1);

      now = now.add(const Duration(milliseconds: 500));
      await cubit.scanSku('SKU001'); // well past the window → accepted
      expect(cubit.state.lines.single.quantity, 2);
    });

    test('distinct SKUs create distinct lines', () async {
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.scanSku('SKU001');
      now = now.add(const Duration(seconds: 1));
      await cubit.scanSku('SKU002');

      expect(cubit.state.lines.map((l) => l.sku), ['SKU001', 'SKU002']);
    });

    test('manual add uses the given quantity and is not debounced', () async {
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.addSkuManual('SKU001', quantity: 5);
      await cubit.addSkuManual('SKU001', quantity: 3); // same clock, still adds

      expect(cubit.state.lines.single.quantity, 8);
    });

    test('manual add rejects a non-positive quantity', () async {
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.addSkuManual('SKU001', quantity: 0);

      expect(cubit.state.lines, isEmpty);
      expect(cubit.state.skuError, isNotNull);
    });
  });

  group('edit / remove before save', () {
    test('setLineQuantity overwrites the quantity', () async {
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.scanSku('SKU001');

      cubit.setLineQuantity('i1', 12);

      expect(cubit.state.lines.single.quantity, 12);
    });

    test('setLineQuantity to zero or less removes the line', () async {
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.scanSku('SKU001');

      cubit.setLineQuantity('i1', 0);

      expect(cubit.state.lines, isEmpty);
    });

    test('removeLine drops just that SKU', () async {
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.scanSku('SKU001');
      now = now.add(const Duration(seconds: 1));
      await cubit.scanSku('SKU002');

      cubit.removeLine('i1');

      expect(cubit.state.lines.map((l) => l.sku), ['SKU002']);
    });
  });

  group('save', () {
    test('cannot save without a warehouse or without lines', () async {
      seedHierarchy();
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);

      // No warehouse, no lines.
      expect(cubit.state.canSave, isFalse);
      await cubit.save();
      expect(recordLocal.saved, isEmpty);

      // Warehouse but no lines → still cannot save.
      await cubit.validateWarehouse('WH001');
      expect(cubit.state.canSave, isFalse);
    });

    test('saves a local record stamped isOffline = true with all fields',
        () async {
      seedHierarchy();
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.validateWarehouse('WH001');
      await cubit.selectRack('r1');
      cubit.selectBin('b1');
      await cubit.scanSku('SKU001');
      now = now.add(const Duration(seconds: 1));
      await cubit.scanSku('SKU002');

      expect(cubit.state.canSave, isTrue);
      await cubit.save();

      expect(cubit.state.saveStatus, SaveStatus.saved);
      final saved = recordLocal.saved.single;
      expect(saved.isOffline, isTrue);
      expect(saved.warehouseId, 'w1');
      expect(saved.rackId, 'r1');
      expect(saved.binId, 'b1');
      expect(saved.items.map((l) => l.sku), ['SKU001', 'SKU002']);
      expect(cubit.state.savedRecordId, saved.id);
    });

    test('rack and bin are optional (record saves with them null)', () async {
      seedHierarchy();
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.validateWarehouse('WH001');
      await cubit.scanSku('SKU001');
      await cubit.save();

      final saved = recordLocal.saved.single;
      expect(saved.rackId, isNull);
      expect(saved.binId, isNull);
      expect(saved.isOffline, isTrue);
    });

    test('isOffline is true in the sync-facing JSON and never flipped', () async {
      seedHierarchy();
      seedItems();
      final cubit = build();
      addTearDown(cubit.close);

      await cubit.validateWarehouse('WH001');
      await cubit.scanSku('SKU001');
      await cubit.save();

      final saved = recordLocal.saved.single;
      // The whole flow only ever writes isOffline = true; there is no code path
      // that sets it to false.
      expect(saved.toJson()['isOffline'], true);
    });
  });
}
