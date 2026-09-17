import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/features/scanning/data/models/scan_result.dart';
import 'package:iams_mobile/features/scanning/presentation/scanner/scanner_cubit.dart';
import 'package:iams_mobile/features/scanning/presentation/scanner/scanner_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockScannerCubit extends MockCubit<ScannerState>
    implements ScannerCubit {}

void main() {
  late MockScannerCubit cubit;

  setUp(() {
    cubit = MockScannerCubit();
    if (sl.isRegistered<ScannerCubit>()) sl.unregister<ScannerCubit>();
    sl.registerFactory<ScannerCubit>(() => cubit);
  });

  tearDown(() => sl.reset());

  Future<void> pump(WidgetTester tester, ScannerState state) async {
    whenListen(cubit, const Stream<ScannerState>.empty(),
        initialState: state);
    await tester.pumpWidget(const MaterialApp(home: ScannerScreen()));
    await tester.pump();
  }

  testWidgets('scanning state shows viewport + manual entry + flash/batch',
      (tester) async {
    await pump(tester, const ScannerState());
    expect(find.byKey(const Key('manual_code_field')), findsOneWidget);
    expect(find.byKey(const Key('flash_toggle')), findsOneWidget);
    expect(find.byKey(const Key('batch_toggle')), findsOneWidget);
  });

  testWidgets('permission-denied is a distinct state', (tester) async {
    await pump(tester, const ScannerState(cameraPermissionDenied: true));
    expect(find.byKey(const Key('scan_permission_denied')), findsOneWidget);
  });

  testWidgets('blocked (cross-tenant) never reads as "not found"',
      (tester) async {
    await pump(
      tester,
      const ScannerState(
        lastResult: ScanResult(
            resolvedType: ResolvedType.blocked, scanEventId: 'e', rawCode: 'X'),
      ),
    );
    expect(find.byKey(const Key('scan_blocked')), findsOneWidget);
    expect(find.byKey(const Key('scan_no_match')), findsNothing);
  });

  testWidgets('no-match state renders its own banner', (tester) async {
    await pump(
      tester,
      const ScannerState(
        lastResult: ScanResult(
            resolvedType: ResolvedType.noMatch, scanEventId: 'e', rawCode: 'ZZ'),
      ),
    );
    expect(find.byKey(const Key('scan_no_match')), findsOneWidget);
  });

  testWidgets('manual submit calls the cubit', (tester) async {
    when(() => cubit.submitManual(any())).thenAnswer((_) async {});
    await pump(tester, const ScannerState());

    await tester.enterText(find.byKey(const Key('manual_code_field')), 'SKU-9');
    await tester.tap(find.byKey(const Key('manual_submit')));
    await tester.pump();

    verify(() => cubit.submitManual('SKU-9')).called(1);
  });
}
