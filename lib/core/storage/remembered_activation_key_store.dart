import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers the Activation Key this device was last activated with, so a
/// returning user can resume with a single tap instead of retyping it.
///
/// Deliberately a **separate** secret from the auth session ([TokenStore]):
/// [logout] clears the session but must leave the remembered key intact (the
/// whole point of "one activation, permanent per-device login"). Only an
/// explicit "forget this device" action ([clear]) or a failed resume removes
/// it. Mirrors [DeviceIdProvider]'s small-persistent-secret shape rather than
/// being folded into the session store.
///
/// Stores the raw key the user actually typed — the server never echoes the
/// key back, so it cannot be reconstructed from the activation response.
abstract class RememberedActivationKeyStore {
  Future<String?> read();
  Future<void> write(String activationKey);
  Future<void> clear();
}

class SecureRememberedActivationKeyStore
    implements RememberedActivationKeyStore {
  SecureRememberedActivationKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  static const _key = 'iams.activation.key';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  @override
  Future<void> write(String activationKey) =>
      _storage.write(key: _key, value: activationKey);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
