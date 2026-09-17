import 'package:equatable/equatable.dart';

/// The kind of entity a raw scanned/typed code resolved to, mirroring the
/// backend contract's `resolvedType` (`Sku | Location | Asset | NoMatch |
/// Blocked`). [unknown] is a forward-compat catch-all so a value the server
/// adds later can never crash the routing switch.
///
/// [blocked] (BR-003, cross-tenant) is deliberately distinct from [noMatch]:
/// the code matches a real entity that exists **outside** the caller's
/// reachable set. It must never be presented as "not found" — the entity
/// exists, it just isn't yours, and its id is never leaked.
///
/// [asset] is reserved for F5 (Fixed Assets) and is **never emitted by the
/// current server**; the client tolerates it now so F5 shipping is not a
/// breaking change.
enum ResolvedType {
  sku,
  location,
  asset,
  noMatch,
  blocked,
  unknown;

  static ResolvedType fromWire(String? value) => switch (value) {
        'Sku' => ResolvedType.sku,
        'Location' => ResolvedType.location,
        'Asset' => ResolvedType.asset,
        'NoMatch' => ResolvedType.noMatch,
        'Blocked' => ResolvedType.blocked,
        _ => ResolvedType.unknown,
      };
}

/// The outcome of `POST /api/scan/resolve` for one raw code. `resolvedEntityId`
/// is null for [ResolvedType.noMatch] and [ResolvedType.blocked] (no id leak);
/// `label` is the item name / bin label when known, else null.
class ScanResult extends Equatable {
  const ScanResult({
    required this.resolvedType,
    required this.scanEventId,
    this.resolvedEntityId,
    this.label,
    this.rawCode,
  });

  final ResolvedType resolvedType;
  final String scanEventId;
  final String? resolvedEntityId;
  final String? label;

  /// The raw code that produced this result — not from the server, stamped by
  /// the client so the "last scanned" affordance and no-match/blocked states
  /// can echo what was scanned.
  final String? rawCode;

  factory ScanResult.fromJson(Map<String, dynamic> json, {String? rawCode}) =>
      ScanResult(
        resolvedType: ResolvedType.fromWire(json['resolvedType'] as String?),
        scanEventId: json['scanEventId'] as String,
        resolvedEntityId: json['resolvedEntityId'] as String?,
        label: json['label'] as String?,
        rawCode: rawCode,
      );

  ScanResult withRawCode(String code) => ScanResult(
        resolvedType: resolvedType,
        scanEventId: scanEventId,
        resolvedEntityId: resolvedEntityId,
        label: label,
        rawCode: code,
      );

  @override
  List<Object?> get props =>
      [resolvedType, scanEventId, resolvedEntityId, label, rawCode];
}
