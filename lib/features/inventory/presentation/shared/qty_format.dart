/// Formats a decimal on-hand/quantity for display: whole numbers render without
/// a trailing `.0`, fractional values keep up to three decimals (trailing
/// zeros trimmed). Kept in one place so every inventory screen reads the same.
String formatQty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  final s = value.toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// A signed quantity, e.g. `+5` / `-3`, for adjustments and pending deltas.
String formatSignedQty(double value) {
  final sign = value > 0 ? '+' : '';
  return '$sign${formatQty(value)}';
}

/// Shortens a GUID to a stable, human-scannable tail (e.g. `Bin …a1b2c3`).
/// Interim until bin labels are resolved from the master-data hierarchy.
String shortId(String id) =>
    id.length <= 6 ? id : '…${id.substring(id.length - 6)}';
