import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/scanning/data/models/scan_result.dart';
import 'package:iams_mobile/features/scanning/data/scan_repository.dart';
import 'package:iams_mobile/features/scanning/presentation/scanner/scanner_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockScanRepository extends Mock implements ScanRepository {}

ScanResult _sku(String code) => ScanResult(
      resolvedType: ResolvedType.sku,
      scanEventId: 'evt',
      resolvedEntityId: 'item-1',
      label: 'Widget',
      rawCode: code,
    );

void main() {
  late MockScanRepository repo;
  late ScannerCubit cubit;

  setUp(() {
    repo = MockScanRepository();
    cubit = ScannerCubit(repo);
  });

  tearDown(() => cubit.close());

  group('toggles & permission', () {
    test('flash and batch toggles flip', () {
      expect(cubit.state.flashOn, isFalse);
      cubit.toggleFlash();
      expect(cubit.state.flashOn, isTrue);
      cubit.toggleBatch();
      expect(cubit.state.batchMode, isTrue);
    });

    test('permission-denied is a settable distinct state', () {
      cubit.setCameraPermissionDenied(true);
      expect(cubit.state.cameraPermissionDenied, isTrue);
    });
  });

  group('resolve outcomes', () {
    test('resolved SKU is stored as lastResult', () async {
      when(() => repo.resolve('SKU-1')).thenAnswer((_) async => _sku('SKU-1'));
      await cubit.onScanned('SKU-1');
      expect(cubit.state.lastResult!.resolvedType, ResolvedType.sku);
      expect(cubit.state.resolving, isFalse);
    });

    test('blocked (out-of-scope) is distinct from no-match', () async {
      when(() => repo.resolve('X')).thenAnswer((_) async => const ScanResult(
          resolvedType: ResolvedType.blocked, scanEventId: 'e'));
      await cubit.onScanned('X');
      expect(cubit.state.lastResult!.resolvedType, ResolvedType.blocked);
      expect(cubit.state.lastResult!.resolvedEntityId, isNull);
    });

    test('ApiException surfaces an error, clears resolving', () async {
      when(() => repo.resolve(any())).thenThrow(
          const ApiException(code: ApiErrorCode.network, message: 'offline'));
      await cubit.onScanned('X');
      expect(cubit.state.hasError, isTrue);
      expect(cubit.state.resolving, isFalse);
    });
  });

  group('duplicate/in-flight guards', () {
    test('batch mode ignores a rapid duplicate of the same code', () async {
      when(() => repo.resolve('DUP')).thenAnswer((_) async => _sku('DUP'));
      cubit.toggleBatch();

      await cubit.onScanned('DUP');
      await cubit.onScanned('DUP'); // within the dedupe window

      verify(() => repo.resolve('DUP')).called(1);
    });

    test('a concurrent second scan is dropped while one is in flight',
        () async {
      final gate = Completer<ScanResult>();
      when(() => repo.resolve('A')).thenAnswer((_) => gate.future);

      final first = cubit.onScanned('A'); // starts, awaits the gate
      await cubit.onScanned('A'); // in-flight → dropped immediately
      gate.complete(_sku('A'));
      await first;

      verify(() => repo.resolve('A')).called(1);
    });

    test('manual entry bypasses the duplicate guard', () async {
      when(() => repo.resolve('M')).thenAnswer((_) async => _sku('M'));
      cubit.toggleBatch();

      await cubit.submitManual('M');
      await cubit.submitManual('M');

      verify(() => repo.resolve('M')).called(2);
    });

    test('batch history accumulates most-recent-first', () async {
      when(() => repo.resolve(any()))
          .thenAnswer((i) async => _sku(i.positionalArguments.first as String));
      cubit.toggleBatch();

      await cubit.onScanned('A');
      await cubit.onScanned('B');

      expect(cubit.state.history.map((r) => r.rawCode).toList(), ['B', 'A']);
    });
  });
}
