// QA live verification, items 10-14, run as PHASES within a single
// `flutter test` process against a real Android emulator + real sqflite +
// the real backend (reached through a fault-injecting proxy at
// API_BASE_URL). Phases share the on-device sqlite file and secure-storage
// session across `relaunch()` calls (see qa_helpers.dart) because
// `flutter test integration_test/*.dart -d <device>` uninstalls the app
// after each separate process invocation on this environment (confirmed:
// `adb shell pm list packages` no longer lists the app immediately after
// QA1's process exited) -- so a literal separate-process-per-phase design
// would silently wipe local state between "relaunches" and defeat the whole
// point of testing resumability. `relaunch()` instead discards only the
// in-memory Dart object graph (GetIt + widget tree), exactly mirroring what
// actually differs across a real OS process kill+relaunch: nothing on disk
// is touched, only what's kept in memory.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/core/storage/app_database.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_api.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_local_data_source.dart';
import 'package:iams_mobile/features/masterdata/data/hierarchy_repository.dart';
import 'package:iams_mobile/features/masterdata/data/models/sync_metadata.dart';

import 'qa_helpers.dart';

Future<Map<String, SyncMetadata?>> allSyncMetadata(
    HierarchyLocalDataSource local) async {
  final out = <String, SyncMetadata?>{};
  for (final level in ['company', 'location', 'warehouse', 'rack', 'bin']) {
    out[level] = await local.readSyncMetadata(level);
  }
  return out;
}

Future<Map<String, int>> tableCounts(HierarchyLocalDataSource local) async {
  final repo = HierarchyRepository(local);
  final companies = await repo.getCompanies();
  var locations = 0, warehouses = 0, racks = 0, bins = 0;
  for (final c in companies) {
    final locs = await repo.getLocations(c.id);
    locations += locs.length;
    for (final l in locs) {
      final whs = await repo.getWarehouses(l.id);
      warehouses += whs.length;
      for (final w in whs) {
        final rs = await repo.getRacks(w.id);
        racks += rs.length;
        for (final r in rs) {
          bins += (await repo.getBins(r.id)).length;
        }
      }
    }
  }
  return {
    'company': companies.length,
    'location': locations,
    'warehouse': warehouses,
    'rack': racks,
    'bin': bins,
  };
}

void main() {
  ensureBinding();

  testWidgets('QA2: partial-failure resume, offline reads, reachability, '
      'duplicate-free relaunches, expired-auth mid-sync', (tester) async {
    // ---- Phase 1: fresh install, sync hits the pre-armed rack fault ----
    await logPhaseMarker('phase1-start');
    await bootApp(tester);
    await activateIfNeeded(tester);
    await pumpUntilFound(
      tester,
      find.text("Couldn't sync your data"),
      timeout: const Duration(seconds: 40),
    );

    var local = sl<HierarchyLocalDataSource>();
    var meta = await allSyncMetadata(local);
    // ignore: avoid_print
    print('PHASE1 sync_metadata=$meta');
    expect(meta['company']!.syncStatus, SyncStatus.complete);
    expect(meta['location']!.syncStatus, SyncStatus.complete);
    expect(meta['warehouse']!.syncStatus, SyncStatus.complete);
    expect(meta['rack']!.syncStatus, SyncStatus.inProgress,
        reason: 'rack fault must leave it inProgress, not complete/failed');
    expect(meta['bin']!.syncStatus, SyncStatus.pending,
        reason: 'bin must never be attempted until rack finishes');

    var counts = await tableCounts(local);
    // ignore: avoid_print
    print('PHASE1 counts=$counts');
    expect(counts['company'], 2);
    expect(counts['location'], 1);
    expect(counts['warehouse'], 1);
    expect(counts['rack'], 0, reason: 'rack request failed, nothing committed');
    expect(counts['bin'], 0, reason: 'bin was never attempted');

    // ---- Phase 2: relaunch (no reinstall) -- must resume from Rack ----
    await logPhaseMarker('phase2-start');
    await relaunch(tester);
    await pumpUntilFound(
      tester,
      find.text('Companies'),
      timeout: const Duration(seconds: 40),
    );

    local = sl<HierarchyLocalDataSource>();
    meta = await allSyncMetadata(local);
    // ignore: avoid_print
    print('PHASE2 sync_metadata=$meta');
    for (final level in ['company', 'location', 'warehouse', 'rack', 'bin']) {
      expect(meta[level]!.syncStatus, SyncStatus.complete,
          reason: '$level must be complete after resume');
    }
    counts = await tableCounts(local);
    // ignore: avoid_print
    print('PHASE2 counts=$counts');
    expect(counts['rack'], 1);
    expect(counts['bin'], 5);

    // ---- Item 11: offline read correctness -- zero network calls for a
    // burst of plain hierarchy reads through the real authenticated Dio. ----
    final authDio = sl<Dio>(instanceName: 'authenticated');
    var requestsDuringReads = 0;
    authDio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      requestsDuringReads++;
      h.next(o);
    }));
    final repo = sl<HierarchyRepository>();
    for (var i = 0; i < 5; i++) {
      await repo.getCompanies();
    }
    final companiesNow = await repo.getCompanies();
    for (final c in companiesNow) {
      final locs = await repo.getLocations(c.id);
      for (final l in locs) {
        final whs = await repo.getWarehouses(l.id);
        for (final w in whs) {
          final rs = await repo.getRacks(w.id);
          for (final r in rs) {
            await repo.getBins(r.id);
          }
        }
      }
    }
    // ignore: avoid_print
    print('PHASE2 offline-read-requests=$requestsDuringReads '
        '(HierarchyRepository has no Api field -- architecturally cannot '
        'reach the network; this counts actual Dio requests on the same '
        'authenticated client the app uses, expecting exactly 0)');
    expect(requestsDuringReads, 0);

    // ---- Phase 3: reachability-gap mitigation, live (item 12) ----
    // (Host-side: a new enabled CompanyConnection was added to Home Co
    // before this test process started -- see the QA harness log for the
    // exact SQL. This phase just verifies the already-installed app picks
    // it up on a warm relaunch, no reinstall.)
    await logPhaseMarker('phase3-start');
    await relaunch(tester);
    await pumpUntilFound(
      tester,
      find.text('Companies'),
      timeout: const Duration(seconds: 40),
    );
    local = sl<HierarchyLocalDataSource>();
    final repo3 = HierarchyRepository(local);
    final companies3 = await repo3.getCompanies();
    // ignore: avoid_print
    print('PHASE3 companies=${companies3.map((c) => c.name).toList()}');
    expect(companies3.map((c) => c.name), contains('Newly Reachable Co'));
    final snapshot3 = await local.readReachableSnapshot();
    expect(snapshot3, hasLength(companies3.length));

    // ---- Phase 4: expired auth mid-sync (item 14) ----
    // Direct probe through the REAL authenticated HierarchyApi/Dio/
    // AuthInterceptor pipeline (pageSize=7 uniquely matches the pre-armed
    // 401 fault so it fires deterministically on this call and no other).
    await logPhaseMarker('phase4-start');
    final api = sl<HierarchyApi>();
    final page = await api.getLocations(pageSize: 7);
    // ignore: avoid_print
    print('PHASE4 probe succeeded after refresh, items=${page.items.length}');
    expect(page.items, isNotEmpty, reason: 'refresh-then-retry must succeed');

    // A subsequent relaunch must still be fully synced and coherent -- the
    // 401 hiccup must not have corrupted sync_metadata or local data.
    await relaunch(tester);
    await pumpUntilFound(
      tester,
      find.text('Companies'),
      timeout: const Duration(seconds: 40),
    );
    local = sl<HierarchyLocalDataSource>();
    meta = await allSyncMetadata(local);
    for (final level in ['company', 'location', 'warehouse', 'rack', 'bin']) {
      expect(meta[level]!.syncStatus, SyncStatus.complete);
    }

    // ---- Phase 5: duplicate/corruption-free across repeated relaunches
    // (item 13) -- two more relaunches, unchanged backend, stable counts,
    // no duplicate primary keys. ----
    final beforeCounts = await tableCounts(local);
    for (var i = 0; i < 2; i++) {
      await logPhaseMarker('phase5-relaunch-$i');
      await relaunch(tester);
      await pumpUntilFound(
        tester,
        find.text('Companies'),
        timeout: const Duration(seconds: 40),
      );
      local = sl<HierarchyLocalDataSource>();
      final c = await tableCounts(local);
      // ignore: avoid_print
      print('PHASE5 relaunch=$i counts=$c');
      expect(c, beforeCounts, reason: 'row counts must stay stable');

      final rawDb = await sl<AppDatabase>().instance;
      for (final table in ['company', 'location', 'warehouse', 'rack', 'bin']) {
        final dupes = await rawDb.rawQuery(
            'SELECT id, COUNT(*) c FROM $table GROUP BY id HAVING c > 1');
        // ignore: avoid_print
        print('PHASE5 relaunch=$i $table duplicate-pk-rows=${dupes.length}');
        expect(dupes, isEmpty,
            reason: '$table must have no duplicate primary keys');
      }
    }
  });
}
