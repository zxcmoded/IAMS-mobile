import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/storage/remembered_activation_key_store.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage storage;
  late SecureRememberedActivationKeyStore store;

  const key = 'iams.activation.key';

  setUp(() {
    storage = MockFlutterSecureStorage();
    store = SecureRememberedActivationKeyStore(storage: storage);
  });

  group('read', () {
    test('returns the stored key when present', () async {
      when(() => storage.read(key: key)).thenAnswer((_) async => 'my-key');
      expect(await store.read(), 'my-key');
    });

    test('returns null when nothing is stored', () async {
      when(() => storage.read(key: key)).thenAnswer((_) async => null);
      expect(await store.read(), isNull);
    });

    test('treats an empty string as no remembered key', () async {
      when(() => storage.read(key: key)).thenAnswer((_) async => '');
      expect(await store.read(), isNull);
    });
  });

  test('write persists the raw key under the dedicated key', () async {
    when(() => storage.write(key: key, value: 'my-key'))
        .thenAnswer((_) async {});
    await store.write('my-key');
    verify(() => storage.write(key: key, value: 'my-key')).called(1);
  });

  test('clear deletes the stored key', () async {
    when(() => storage.delete(key: key)).thenAnswer((_) async {});
    await store.clear();
    verify(() => storage.delete(key: key)).called(1);
  });
}
