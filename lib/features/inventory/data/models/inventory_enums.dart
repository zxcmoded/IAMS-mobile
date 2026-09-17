// Enums shared across the F4 inventory feature — the list filter, the ledger
// transaction/count vocabularies from the contract, and the client-side
// outbox vocabularies for the offline-first mutation queue.

/// The list filter pill, matching the backend `filter` query param exactly.
/// [wire] is the token sent to the server; [all] omits the param (server
/// default).
enum InventoryFilter {
  all,
  inStock,
  lowStock,
  outOfStock;

  String get wire => switch (this) {
        InventoryFilter.all => 'all',
        InventoryFilter.inStock => 'in_stock',
        InventoryFilter.lowStock => 'low_stock',
        InventoryFilter.outOfStock => 'out_of_stock',
      };

  String get label => switch (this) {
        InventoryFilter.all => 'All',
        InventoryFilter.inStock => 'In stock',
        InventoryFilter.lowStock => 'Low',
        InventoryFilter.outOfStock => 'Out of stock',
      };
}

/// Ledger transaction type on a movement row / mutation response.
enum TransactionType {
  receive,
  transfer,
  adjustment,
  unknown;

  static TransactionType fromWire(String? value) => switch (value) {
        'Receive' => TransactionType.receive,
        'Transfer' => TransactionType.transfer,
        'Adjustment' => TransactionType.adjustment,
        _ => TransactionType.unknown,
      };

  String get label => switch (this) {
        TransactionType.receive => 'Received',
        TransactionType.transfer => 'Transferred',
        TransactionType.adjustment => 'Adjusted',
        TransactionType.unknown => 'Movement',
      };
}

/// Status of a ledger movement row.
enum MovementStatus {
  applied,
  pending,
  rejected,
  unknown;

  static MovementStatus fromWire(String? value) => switch (value) {
        'Applied' => MovementStatus.applied,
        'Pending' => MovementStatus.pending,
        'Rejected' => MovementStatus.rejected,
        _ => MovementStatus.unknown,
      };
}

/// Adjudication status of a stock count (contract: `Completed | PendingApproval
/// | Approved | Rejected`).
enum StockCountStatus {
  completed,
  pendingApproval,
  approved,
  rejected,
  unknown;

  static StockCountStatus fromWire(String? value) => switch (value) {
        'Completed' => StockCountStatus.completed,
        'PendingApproval' => StockCountStatus.pendingApproval,
        'Approved' => StockCountStatus.approved,
        'Rejected' => StockCountStatus.rejected,
        _ => StockCountStatus.unknown,
      };

  /// Over-threshold counts park here with **no stock change** until an approval
  /// — the UI must present this as a distinct outcome, not an error.
  bool get isPendingApproval => this == StockCountStatus.pendingApproval;
}

/// Variance threshold interpretation snapshotted onto a count.
enum VarianceThresholdType {
  absoluteQuantity,
  percentage,
  unknown;

  static VarianceThresholdType fromWire(String? value) => switch (value) {
        'AbsoluteQuantity' => VarianceThresholdType.absoluteQuantity,
        'Percentage' => VarianceThresholdType.percentage,
        _ => VarianceThresholdType.unknown,
      };
}

/// Which mutation an outbox row represents. [wire] is the persisted token.
enum MutationKind {
  receive,
  transfer,
  adjust,
  count;

  String get wire => name;

  static MutationKind fromWire(String value) => switch (value) {
        'receive' => MutationKind.receive,
        'transfer' => MutationKind.transfer,
        'adjust' => MutationKind.adjust,
        'count' => MutationKind.count,
        _ => throw ArgumentError('Unknown mutation kind: $value'),
      };

  String get label => switch (this) {
        MutationKind.receive => 'Receive',
        MutationKind.transfer => 'Transfer',
        MutationKind.adjust => 'Adjustment',
        MutationKind.count => 'Stock count',
      };
}

/// Lifecycle of a queued outbox row.
/// - [pending]: committed locally, waiting to push (offline or not-yet-tried).
/// - [synced]: server accepted it (or replayed it); terminal success.
/// - [conflict]: rejected `409 stock_version_conflict`; needs user review.
/// - [failed]: rejected by a business/validation error (422/400/404); terminal
///   failure unless the user edits and resubmits.
enum OutboxStatus {
  pending,
  synced,
  conflict,
  failed;

  String get wire => name;

  static OutboxStatus fromWire(String? value) => switch (value) {
        'synced' => OutboxStatus.synced,
        'conflict' => OutboxStatus.conflict,
        'failed' => OutboxStatus.failed,
        _ => OutboxStatus.pending,
      };

  bool get isTerminalSuccess => this == OutboxStatus.synced;
  bool get needsAttention => this == OutboxStatus.conflict || this == OutboxStatus.failed;
}

/// The outcome the repository reports back to a cubit after attempting a
/// mutation, so the screen can show the right inline state.
enum MutationOutcome {
  /// Applied on the server this attempt (`replayed: false`).
  applied,

  /// Idempotent replay — already committed on a prior attempt (`replayed: true`).
  replayed,

  /// Could not reach the server; left queued in the outbox to retry later.
  queued,

  /// `409 stock_version_conflict` — bin changed under us; queued as conflict.
  conflict,

  /// `422 insufficient_stock` — movement would drive a bin below zero.
  insufficientStock,

  /// A validation/not-found error (400/404) — terminal failure for this payload.
  rejected,
}
