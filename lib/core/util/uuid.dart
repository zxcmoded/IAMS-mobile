import 'dart:math';

/// Generates RFC 4122 version-4 (random) UUIDs without pulling in a package —
/// the app already generates its device id the same way (`Random.secure`),
/// so this keeps the dependency surface unchanged.
///
/// Used for client-generated `idempotencyKey`s on every offline-first
/// inventory mutation: the key is minted once when the mutation is first
/// committed locally and reused verbatim on every retry/replay, so a partial
/// prior success is detected server-side via `"replayed": true` instead of
/// being double-applied.
String newUuidV4([Random? random]) {
  final rnd = random ?? _secure;
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));

  // Set the version (4) and variant (10xx) bits per RFC 4122 §4.4.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
  return '${hex.sublist(0, 4).join()}-'
      '${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-'
      '${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10, 16).join()}';
}

final Random _secure = Random.secure();
