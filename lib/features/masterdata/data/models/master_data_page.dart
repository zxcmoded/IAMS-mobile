/// The response envelope shared by all five master-data listing endpoints:
/// `{ "items": [...], "nextCursor": string|null, "hasMore": bool }`.
///
/// Hand-written generic wrapper (no codegen) — [fromJson] takes the per-item
/// parser so one shape serves every level.
///
/// ⚠️ `nextCursor: null` on an **empty** page means "nothing new since your
/// cursor," NOT "reset." Callers must never clear a stored cursor from an empty
/// page — see [HierarchySyncService].
class MasterDataPage<T> {
  const MasterDataPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<T> items;
  final String? nextCursor;
  final bool hasMore;

  static MasterDataPage<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final rawItems = (json['items'] as List?) ?? const [];
    return MasterDataPage<T>(
      items: rawItems
          .map((e) => itemFromJson((e as Map).cast<String, dynamic>()))
          .toList(growable: false),
      nextCursor: json['nextCursor'] as String?,
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }
}
