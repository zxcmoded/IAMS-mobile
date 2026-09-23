import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/features/access/data/scope_repository.dart';
import 'package:iams_mobile/features/access/presentation/location_select/location_select_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/access_fixtures.dart';

class MockScopeRepository extends Mock implements ScopeRepository {}

void main() {
  late MockScopeRepository repo;
  late LocationSelectCubit cubit;

  setUp(() {
    repo = MockScopeRepository();
    cubit = LocationSelectCubit(repo);
  });

  tearDown(() => cubit.close());

  group('load', () {
    test('loads the caller\'s assigned locations', () async {
      when(() => repo.loadScope()).thenAnswer((_) async =>
          scope(locations: [locRef('l1'), locRef('l2')]));

      await cubit.load();

      expect(cubit.state.status, LocationSelectStatus.loaded);
      expect(cubit.state.locations.map((l) => l.id), ['l1', 'l2']);
      expect(cubit.state.selectedId, isNull); // nothing chosen yet
      expect(cubit.state.canContinue, isFalse);
    });

    test('empty assigned set → loaded but with no locations', () async {
      when(() => repo.loadScope()).thenAnswer((_) async => scope(locations: []));

      await cubit.load();

      expect(cubit.state.status, LocationSelectStatus.loaded);
      expect(cubit.state.hasLocations, isFalse);
    });

    test('preselects a still-assigned previous choice', () async {
      when(() => repo.loadScope()).thenAnswer(
          (_) async => scope(locations: [locRef('l1'), locRef('l2')]));

      await cubit.load(preselectId: 'l2');

      expect(cubit.state.selectedId, 'l2');
      expect(cubit.state.canContinue, isTrue);
    });

    test('ignores a preselect that is no longer assigned', () async {
      when(() => repo.loadScope()).thenAnswer(
          (_) async => scope(locations: [locRef('l1')]));

      await cubit.load(preselectId: 'gone');

      expect(cubit.state.selectedId, isNull);
    });

    test('a connectivity failure shows the explicit offline message', () async {
      when(() => repo.loadScope()).thenThrow(const ApiException(
        code: ApiErrorCode.network,
        message: 'mock message from backend',
      ));

      await cubit.load();

      expect(cubit.state.status, LocationSelectStatus.error);
      expect(cubit.state.errorMessage, contains("You're offline"));
    });

    test('a non-network ApiException surfaces its own message', () async {
      when(() => repo.loadScope()).thenThrow(const ApiException(
        code: ApiErrorCode.accessDenied,
        statusCode: 403,
        message: 'You do not have access.',
      ));

      await cubit.load();

      expect(cubit.state.status, LocationSelectStatus.error);
      expect(cubit.state.errorMessage, 'You do not have access.');
    });

    test('a non-ApiException failure yields a generic, retryable error',
        () async {
      when(() => repo.loadScope()).thenThrow(StateError('boom'));

      await cubit.load();

      expect(cubit.state.status, LocationSelectStatus.error);
      expect(cubit.state.errorMessage, 'Something went wrong. Please try again.');
    });
  });

  group('choose', () {
    test('records the selection and enables Continue', () async {
      when(() => repo.loadScope()).thenAnswer(
          (_) async => scope(locations: [locRef('l1'), locRef('l2')]));
      await cubit.load();

      cubit.choose('l1');

      expect(cubit.state.selectedId, 'l1');
      expect(cubit.state.canContinue, isTrue);
    });
  });
}
