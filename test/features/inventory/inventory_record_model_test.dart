import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_record.dart';

void main() {
  InventoryRecord sample() => InventoryRecord(
        id: 'local-1',
        warehouseId: 'WH001',
        warehouseName: 'Warehouse 1',
        rackId: 'RACK001',
        rackName: 'Rack 1',
        binId: 'BIN001',
        binName: 'Bin 1',
        items: const [
          InventoryRecordLine(
              inventoryItemId: 'i1', sku: 'SKU001', name: 'A', quantity: 10),
          InventoryRecordLine(
              inventoryItemId: 'i2', sku: 'SKU002', name: 'B', quantity: 5),
        ],
        createdAtUtc: DateTime.utc(2026, 1, 1),
      );

  test('toJson matches the spec shape and defaults isOffline true', () {
    final json = sample().toJson();
    expect(json['id'], 'local-1');
    expect(json['warehouseId'], 'WH001');
    expect(json['rackId'], 'RACK001');
    expect(json['binId'], 'BIN001');
    expect(json['isOffline'], true);
    final items = json['items'] as List;
    expect(items.length, 2);
    expect((items.first as Map)['sku'], 'SKU001');
    expect((items.first as Map)['quantity'], 10);
  });

  test('row round-trip preserves header + lines and the offline flag', () {
    final r = sample();
    final headerRow = r.toRow();
    expect(headerRow['is_offline'], 1);

    final lineRows =
        r.items.map((l) => l.toRow(r.id)).toList(growable: false);
    final rebuilt = InventoryRecord.fromRow(
      headerRow,
      lineRows.map(InventoryRecordLine.fromRow).toList(),
    );

    expect(rebuilt.id, r.id);
    expect(rebuilt.warehouseId, r.warehouseId);
    expect(rebuilt.rackId, r.rackId);
    expect(rebuilt.binId, r.binId);
    expect(rebuilt.isOffline, isTrue);
    expect(rebuilt.items.map((l) => l.sku), ['SKU001', 'SKU002']);
    expect(rebuilt.totalQuantity, 15);
  });

  test('totalQuantity sums the line quantities', () {
    expect(sample().totalQuantity, 15);
  });
}
