import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/inventory/data/inventory_record_repository.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_record.dart';
import 'package:iams_mobile/features/inventory/presentation/records/inventory_records_cubit.dart';

import '../../support/inventory_fixtures.dart';

InventoryRecord recordFixture(
  String id, {
  DateTime? createdAt,
  bool isOffline = true,
}) =>
    InventoryRecord(
      id: id,
      warehouseId: 'w1',
      warehouseName: 'WH001',
      items: const [
        InventoryRecordLine(
          inventoryItemId: 'i1',
          sku: 'SKU001',
          name: 'Widget',
          quantity: 3,
        ),
      ],
      isOffline: isOffline,
      createdAtUtc: createdAt ?? DateTime.utc(2026, 1, 1),
    );

void main() {
  late FakeInventoryRecordLocalDataSource local;
  late InventoryRecordRepository repo;

  setUp(() {
    local = FakeInventoryRecordLocalDataSource();
    repo = InventoryRecordRepository(local);
  });

  test('loads saved records newest-first', () async {
    await repo.create(recordFixture('a', createdAt: DateTime.utc(2026, 1, 1)));
    await repo.create(recordFixture('b', createdAt: DateTime.utc(2026, 1, 3)));
    await repo.create(recordFixture('c', createdAt: DateTime.utc(2026, 1, 2)));

    final cubit = InventoryRecordsCubit(repo);
    addTearDown(cubit.close);
    await cubit.load();

    expect(cubit.state.status, InventoryRecordsStatus.loaded);
    expect(cubit.state.records.map((r) => r.id), ['b', 'c', 'a']);
    // Every locally-created record is flagged offline.
    expect(cubit.state.records.every((r) => r.isOffline), isTrue);
  });

  test('empty when nothing saved', () async {
    final cubit = InventoryRecordsCubit(repo);
    addTearDown(cubit.close);
    await cubit.load();

    expect(cubit.state.status, InventoryRecordsStatus.loaded);
    expect(cubit.state.isEmpty, isTrue);
  });
}
