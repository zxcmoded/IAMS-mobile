// Item 9: fresh install -> activate -> the /sync screen drives Company..Bin
// into the REAL on-device sqflite database, then navigates on.
//
// NOTE (QA finding): `/companies` (CompanySelectorScreen) is NOT wired to the
// new HierarchyRepository -- it calls the pre-existing online `/me/scope` API
// via TenantRepository/TenantApi (confirmed by reading
// lib/features/tenant/presentation/scope/company_selector_screen.dart and
// lib/features/tenant/data/tenant_repository.dart: no HierarchyRepository
// reference anywhere). `HierarchyRepository` is registered in
// service_locator.dart but never injected into any cubit/screen (grep across
// lib/ turns up zero consumers). So there is currently NO UI screen that
// reads the synced offline hierarchy at all. This test therefore verifies the
// sync outcome by calling the real `HierarchyRepository`/
// `HierarchyLocalDataSource` directly against the same GetIt-wired,
// real-sqflite instance the app just populated -- the most faithful
// "real database" check available given that gap.
import 'package:flutter_test/flutter_test.dart';

import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_repository.dart';

import 'qa_helpers.dart';

void main() {
  ensureBinding();

  testWidgets('QA1: fresh install full sync populates real sqflite',
      (tester) async {
    await bootApp(tester);
    await activateIfNeeded(tester);

    // Wait for the sync screen to finish and hand off to /companies (proves
    // HierarchySyncCubit reached `complete`).
    await pumpUntilFound(
      tester,
      find.text('Companies'),
      timeout: const Duration(seconds: 40),
    );

    final repo = sl<HierarchyRepository>();
    final companies = await repo.getCompanies();
    // ignore: avoid_print
    print('QA1 companies=${companies.map((c) => c.name).toList()}');
    expect(companies.map((c) => c.name).toSet(),
        {'Home Co', 'Reachable Co (enabled)'});

    final home = companies.firstWhere((c) => c.name == 'Home Co');
    final locations = await repo.getLocations(home.id);
    expect(locations, hasLength(1));
    final warehouses = await repo.getWarehouses(locations.first.id);
    expect(warehouses, hasLength(1));
    final racks = await repo.getRacks(warehouses.first.id);
    expect(racks, hasLength(1));
    final bins = await repo.getBins(racks.first.id);
    expect(bins, hasLength(5));
    // ignore: avoid_print
    print('QA1 bins=${bins.map((b) => '${b.name}:${b.isActive}').toList()}');
  });
}
