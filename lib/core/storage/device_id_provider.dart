import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Supplies a stable, per-install `deviceId` sent on `activate` (required —
/// the single enforcement point for device binding). Generated once and
/// persisted; not tied to any hardware identifier (privacy-friendly, and the
/// server performs no device attestation).
abstract class DeviceIdProvider {
  Future<String> getDeviceId();
}

class PersistentDeviceIdProvider implements DeviceIdProvider {
  PersistentDeviceIdProvider({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'iams.device.id';
  final FlutterSecureStorage _storage;
  String? _cached;

  @override
  Future<String> getDeviceId() async {
    if (_cached != null) return _cached!;
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) {
      return _cached = existing;
    }
    final generated = _generate();
    await _storage.write(key: _key, value: generated);
    return _cached = generated;
  }

  String _generate() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
