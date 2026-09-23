import '../../../core/util/uuid.dart';
import 'models/audit_record.dart';

/// A single failed field within an import row (e.g. `Qty` is negative).
class AuditFieldError {
  const AuditFieldError(this.field, this.reason);

  /// The spec column name (`Warehouse`, `SKU`, `Qty`).
  final String field;

  /// Human-readable reason (e.g. "is required", "must be a non-negative number").
  final String reason;

  @override
  String toString() => '$field $reason';
}

/// All validation failures for one data row of an import file.
class AuditRowError {
  const AuditRowError(this.rowNumber, this.fieldErrors);

  /// 1-based row number **as it appears in the file** — the header is row 1, so
  /// the first data row is row 2. This is what the user sees in Excel, making
  /// errors easy to locate.
  final int rowNumber;
  final List<AuditFieldError> fieldErrors;

  /// A compact one-line description, e.g. "Row 3: Warehouse is required; Qty
  /// must be a non-negative number".
  String get summary =>
      'Row $rowNumber: ${fieldErrors.map((e) => e.toString()).join('; ')}';
}

/// The outcome of parsing + validating an import file, computed BEFORE anything
/// is persisted. Carries the rows that passed ([validRecords]), the rows that
/// failed with per-row/per-field attribution ([rowErrors]), and — when the file
/// itself was unusable (empty, or missing required header columns) — a
/// [fileError] that blocks the whole import.
class AuditImportResult {
  const AuditImportResult({
    this.validRecords = const [],
    this.rowErrors = const [],
    this.fileError,
    this.totalDataRows = 0,
  });

  final List<AuditRecord> validRecords;
  final List<AuditRowError> rowErrors;

  /// Set only when the file as a whole cannot be imported (empty file, or the
  /// header is missing a required column). When set, [validRecords] is empty.
  final String? fileError;

  /// Count of non-blank data rows examined (valid + invalid).
  final int totalDataRows;

  bool get hasFileError => fileError != null;
  bool get hasRowErrors => rowErrors.isNotEmpty;
  bool get hasValidRecords => validRecords.isNotEmpty;
  int get validCount => validRecords.length;
  int get errorCount => rowErrors.length;
}

/// Pure-Dart parser/validator for Audit imports. Takes an already-decoded table
/// (the CSV/XLSX decoders in [AuditFileService] turn a file into
/// `List<List<Object?>>`) and returns an [AuditImportResult]. Kept free of any
/// file/plugin I/O so the validation rules are fully unit-testable.
///
/// Column mapping is **by header name** (case-insensitive, trimmed), not by
/// position, so a file whose columns are reordered — or that carries extra
/// columns — still imports correctly as long as the required headers are present.
///
/// Validation rules (per the spec):
/// - `Warehouse` required (non-empty after trim)
/// - `SKU` required (non-empty after trim)
/// - `Qty` required and a valid, finite, non-negative number
/// - `Rack` / `Bin` optional (may be blank)
class AuditImportParser {
  const AuditImportParser._();

  /// Header labels required to be present for the file to be importable at all.
  static const _requiredHeaders = ['Warehouse', 'SKU', 'Qty'];

  static AuditImportResult parse(
    List<List<Object?>> rows, {
    String Function()? idFactory,
    DateTime? now,
  }) {
    final mintId = idFactory ?? newUuidV4;
    final createdAt = (now ?? DateTime.now()).toUtc();

    // The header is the first non-blank row. We keep the original row indices
    // (rather than filtering blanks up front) so reported row numbers always
    // match what the user sees in Excel, even when blank rows are interspersed.
    var headerRowIndex = -1;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].any((c) => _cell(c).isNotEmpty)) {
        headerRowIndex = i;
        break;
      }
    }
    if (headerRowIndex == -1) {
      return const AuditImportResult(
        fileError: 'The file is empty. Use the sample template as a starting '
            'point.',
      );
    }

    final header = rows[headerRowIndex];
    final headerIndex = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final key = _cell(header[i]).toLowerCase();
      if (key.isNotEmpty) headerIndex.putIfAbsent(key, () => i);
    }

    final missing = _requiredHeaders
        .where((h) => !headerIndex.containsKey(h.toLowerCase()))
        .toList();
    if (missing.isNotEmpty) {
      return AuditImportResult(
        fileError: 'The file is missing required column(s): '
            '${missing.join(', ')}. Expected columns: '
            '${AuditRecord.columns.join(', ')}.',
      );
    }

    final wIdx = headerIndex['warehouse']!;
    final sIdx = headerIndex['sku']!;
    final qIdx = headerIndex['qty']!;
    final rIdx = headerIndex['rack'];
    final bIdx = headerIndex['bin'];

    final valid = <AuditRecord>[];
    final errors = <AuditRowError>[];
    var dataRows = 0;

    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      // Skip fully-blank rows (common trailing/interspersed spreadsheet empties)
      // — they are neither counted nor reported as errors.
      if (row.every((c) => _cell(c).isEmpty)) continue;
      dataRows++;
      final rowNumber = i + 1; // 1-based row number as it appears in the file.

      final warehouse = _at(row, wIdx);
      final sku = _at(row, sIdx);
      final qtyRaw = _at(row, qIdx);
      final rack = rIdx == null ? '' : _at(row, rIdx);
      final bin = bIdx == null ? '' : _at(row, bIdx);

      final fieldErrors = <AuditFieldError>[];
      if (warehouse.isEmpty) {
        fieldErrors.add(const AuditFieldError('Warehouse', 'is required'));
      }
      if (sku.isEmpty) {
        fieldErrors.add(const AuditFieldError('SKU', 'is required'));
      }

      double? qty;
      if (qtyRaw.isEmpty) {
        fieldErrors.add(const AuditFieldError('Qty', 'is required'));
      } else {
        final parsed = num.tryParse(qtyRaw);
        if (parsed == null || !parsed.isFinite) {
          fieldErrors.add(
              const AuditFieldError('Qty', 'must be a valid number'));
        } else if (parsed < 0) {
          fieldErrors
              .add(const AuditFieldError('Qty', 'must not be negative'));
        } else {
          qty = parsed.toDouble();
        }
      }

      if (fieldErrors.isNotEmpty) {
        errors.add(AuditRowError(rowNumber, fieldErrors));
        continue;
      }

      valid.add(AuditRecord(
        id: mintId(),
        warehouse: warehouse,
        rack: rack.isEmpty ? null : rack,
        bin: bin.isEmpty ? null : bin,
        sku: sku,
        qty: qty!,
        createdAtUtc: createdAt,
      ));
    }

    return AuditImportResult(
      validRecords: valid,
      rowErrors: errors,
      totalDataRows: dataRows,
    );
  }

  static String _at(List<Object?> row, int index) =>
      index < row.length ? _cell(row[index]) : '';

  static String _cell(Object? value) => value?.toString().trim() ?? '';
}
