/// Formats an audit quantity for display and for file export: whole numbers
/// render without a trailing `.0` (so `10.0` → `10`, matching the spec's sample
/// template), fractional values keep up to three decimals with trailing zeros
/// trimmed. Kept in the data layer because both the export writer
/// (`AuditFileService`) and the screen render quantities the same way.
String formatAuditQty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  final s = value.toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
