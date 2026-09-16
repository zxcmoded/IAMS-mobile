import 'package:equatable/equatable.dart';

/// Per-level sync progress. `pending` = not started (or force-reset by a
/// reachable-set change); `inProgress` = persisted before the first network
/// call so a crash mid-page still resumes rather than looking untouched;
/// `complete` = fully caught up this pass; `failed` reserved for an explicit
/// terminal failure (the sync service leaves a partial level at `inProgress`).
enum SyncStatus {
  pending,
  inProgress,
  complete,
  failed;

  /// Wire/DB token (matches the `sync_status` TEXT column). Uses the same
  /// snake-ish tokens the schema DEFAULT ('pending') implies.
  String get token => switch (this) {
        SyncStatus.pending => 'pending',
        SyncStatus.inProgress => 'inProgress',
        SyncStatus.complete => 'complete',
        SyncStatus.failed => 'failed',
      };

  static SyncStatus fromToken(String? token) => switch (token) {
        'inProgress' => SyncStatus.inProgress,
        'complete' => SyncStatus.complete,
        'failed' => SyncStatus.failed,
        _ => SyncStatus.pending,
      };
}

/// One row of the `sync_metadata` table — the durable cursor + status for a
/// single hierarchy level (`entity` is the level name: `company`, `location`,
/// …). [lastCursor] is the opaque server cursor; it is only ever advanced from
/// a non-empty page and never cleared on an empty page.
class SyncMetadata extends Equatable {
  const SyncMetadata({
    required this.entity,
    this.lastCursor,
    this.syncStatus = SyncStatus.pending,
    this.lastSyncedAtUtc,
    this.syncVersion = 0,
  });

  final String entity;
  final String? lastCursor;
  final SyncStatus syncStatus;
  final DateTime? lastSyncedAtUtc;
  final int syncVersion;

  factory SyncMetadata.fromRow(Map<String, Object?> row) => SyncMetadata(
        entity: row['entity'] as String,
        lastCursor: row['last_cursor'] as String?,
        syncStatus: SyncStatus.fromToken(row['sync_status'] as String?),
        lastSyncedAtUtc: row['last_synced_at_utc'] == null
            ? null
            : DateTime.parse(row['last_synced_at_utc'] as String).toUtc(),
        syncVersion: (row['sync_version'] as int?) ?? 0,
      );

  Map<String, Object?> toRow() => {
        'entity': entity,
        'last_cursor': lastCursor,
        'sync_status': syncStatus.token,
        'last_synced_at_utc': lastSyncedAtUtc?.toIso8601String(),
        'sync_version': syncVersion,
      };

  SyncMetadata copyWith({
    String? entity,
    String? lastCursor,
    SyncStatus? syncStatus,
    DateTime? lastSyncedAtUtc,
    int? syncVersion,
  }) =>
      SyncMetadata(
        entity: entity ?? this.entity,
        lastCursor: lastCursor ?? this.lastCursor,
        syncStatus: syncStatus ?? this.syncStatus,
        lastSyncedAtUtc: lastSyncedAtUtc ?? this.lastSyncedAtUtc,
        syncVersion: syncVersion ?? this.syncVersion,
      );

  @override
  List<Object?> get props =>
      [entity, lastCursor, syncStatus, lastSyncedAtUtc, syncVersion];
}
