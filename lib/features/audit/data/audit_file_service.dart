import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'audit_export_encoder.dart';
import 'audit_import_parser.dart';
import 'models/audit_record.dart';

/// The two file formats the Audit feature can import and export.
enum AuditFileFormat {
  csv('csv', 'text/csv'),
  xlsx('xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

  const AuditFileFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

/// Raised when a picked file can't be decoded (unsupported/corrupt bytes). Kept
/// distinct from a validation failure (which is reported per-row via
/// [AuditImportResult]) so the cubit can show a different message.
class AuditFileException implements Exception {
  const AuditFileException(this.message);
  final String message;
  @override
  String toString() => 'AuditFileException: $message';
}

/// Abstraction over the device's file picker / file writer / share sheet. The
/// cubit depends on this interface (not the concrete impl) so its import/export
/// flows can be unit-tested with a fake — the real plugins (`file_picker`,
/// `path_provider`, `share_plus`) never run under `flutter test`.
///
/// Nothing here touches the network: import reads a local file the user picks,
/// export writes a local file and hands it to the OS share sheet.
abstract class AuditFileService {
  /// Opens the OS picker for a `.csv`/`.xlsx` file, decodes it, and validates
  /// every row. Returns `null` if the user cancelled the picker. Throws
  /// [AuditFileException] if the chosen file can't be decoded.
  Future<AuditImportResult?> pickAndParse();

  /// Writes [records] to a temp file in [format] (same column structure as the
  /// template) and opens the OS share sheet so the user can save/send it.
  /// Returns the generated file name.
  Future<String> exportRecords(
      List<AuditRecord> records, AuditFileFormat format);

  /// Writes the sample template — the header row plus two illustrative example
  /// rows — in [format] and opens the share sheet. Returns the file name.
  Future<String> exportTemplate(AuditFileFormat format);
}

/// Real implementation backed by `file_picker` + `path_provider` + `share_plus`
/// and the pure-Dart `csv`/`excel` codecs.
class PlatformAuditFileService implements AuditFileService {
  const PlatformAuditFileService();

  @override
  Future<AuditImportResult?> pickAndParse() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [AuditFileFormat.csv.extension, AuditFileFormat.xlsx.extension],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null; // user cancelled

    final file = picked.files.single;
    final bytes = file.bytes ?? await _readPathBytes(file.path);
    if (bytes == null) {
      throw const AuditFileException('Could not read the selected file.');
    }

    final ext = (file.extension ?? p.extension(file.name).replaceAll('.', ''))
        .toLowerCase();

    final List<List<Object?>> table;
    if (ext == AuditFileFormat.csv.extension) {
      table = _decodeCsv(bytes);
    } else if (ext == AuditFileFormat.xlsx.extension) {
      table = _decodeXlsx(bytes);
    } else {
      throw AuditFileException(
          'Unsupported file type ".$ext". Pick a .csv or .xlsx file.');
    }

    return AuditImportParser.parse(table);
  }

  @override
  Future<String> exportRecords(
          List<AuditRecord> records, AuditFileFormat format) =>
      _writeAndShare('audit_export', format, records);

  @override
  Future<String> exportTemplate(AuditFileFormat format) =>
      _writeAndShare('audit_template', format, AuditExportEncoder.templateRecords);

  // ---- decoding -------------------------------------------------------------

  List<List<Object?>> _decodeCsv(List<int> bytes) {
    // Strip a UTF-8 BOM if present, then let the converter auto-detect the EOL.
    final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('﻿', '');
    return const CsvToListConverter(shouldParseNumbers: false).convert(text);
  }

  List<List<Object?>> _decodeXlsx(List<int> bytes) {
    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const AuditFileException(
          'The .xlsx file could not be read. It may be corrupt.');
    }
    final sheetName = workbook.getDefaultSheet() ??
        (workbook.tables.keys.isNotEmpty ? workbook.tables.keys.first : null);
    if (sheetName == null) {
      throw const AuditFileException('The workbook has no sheets to import.');
    }
    final sheet = workbook.tables[sheetName]!;
    // `cell?.value` is a CellValue? whose toString() yields the plain text /
    // number; the parser stringifies each cell, so passing the CellValue is fine.
    return sheet.rows
        .map((row) => row.map((cell) => cell?.value).toList(growable: false))
        .toList(growable: false);
  }

  // ---- encoding + sharing ---------------------------------------------------

  Future<String> _writeAndShare(
    String baseName,
    AuditFileFormat format,
    List<AuditRecord> records,
  ) async {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final fileName = '${baseName}_$stamp.${format.extension}';
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, fileName);
    final file = File(path);

    switch (format) {
      case AuditFileFormat.csv:
        await file.writeAsString(AuditExportEncoder.toCsv(records));
      case AuditFileFormat.xlsx:
        await file.writeAsBytes(AuditExportEncoder.toXlsx(records));
    }

    await Share.shareXFiles(
      [XFile(path, mimeType: format.mimeType, name: fileName)],
      subject: fileName,
    );
    return fileName;
  }

  Future<List<int>?> _readPathBytes(String? path) async {
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }
}
