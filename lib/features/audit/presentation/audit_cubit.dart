import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/audit_file_service.dart';
import '../data/audit_import_parser.dart';
import '../data/audit_repository.dart';
import '../data/models/audit_record.dart';

/// High-level lifecycle of the Audit screen's stored-records list.
enum AuditStatus { loading, loaded, error }

/// State for the fully-offline Audit screen. Holds the stored records plus two
/// transient overlays:
/// - [pendingImport]: a parsed-but-not-yet-persisted import awaiting the user's
///   decision (import valid rows / cancel). Presented as a review sheet.
/// - [actionMessage]/[actionError]: one-shot feedback for import/export/template
///   actions, surfaced as a SnackBar and cleared after being shown.
class AuditState extends Equatable {
  const AuditState({
    this.status = AuditStatus.loading,
    this.records = const [],
    this.errorMessage,
    this.pendingImport,
    this.isBusy = false,
    this.actionMessage,
    this.actionError,
  });

  final AuditStatus status;
  final List<AuditRecord> records;
  final String? errorMessage;

  /// A parsed import awaiting the user's confirm/cancel. Null when no review is
  /// in progress.
  final AuditImportResult? pendingImport;

  /// True while a long-running action (picking/parsing, writing, exporting) is
  /// in flight — used to disable buttons and show a spinner.
  final bool isBusy;

  /// One-shot success/info message (e.g. "Imported 5 rows"). Cleared once shown.
  final String? actionMessage;

  /// One-shot error message for a failed action. Cleared once shown.
  final String? actionError;

  bool get isEmpty => records.isEmpty;

  AuditState copyWith({
    AuditStatus? status,
    List<AuditRecord>? records,
    String? errorMessage,
    AuditImportResult? pendingImport,
    bool clearPendingImport = false,
    bool? isBusy,
    String? actionMessage,
    String? actionError,
    bool clearMessages = false,
  }) {
    return AuditState(
      status: status ?? this.status,
      records: records ?? this.records,
      errorMessage: errorMessage ?? this.errorMessage,
      pendingImport:
          clearPendingImport ? null : (pendingImport ?? this.pendingImport),
      isBusy: isBusy ?? this.isBusy,
      actionMessage: clearMessages ? null : (actionMessage ?? this.actionMessage),
      actionError: clearMessages ? null : (actionError ?? this.actionError),
    );
  }

  @override
  List<Object?> get props => [
        status,
        records,
        errorMessage,
        pendingImport,
        isBusy,
        actionMessage,
        actionError,
      ];
}

/// Drives the fully-offline Audit screen: loads stored records from local
/// SQLite, imports CSV/XLSX files (validate-before-persist), exports the stored
/// records, and produces the sample template. **No network anywhere** — the
/// repository is local-only and the file service only touches the device's
/// picker/storage/share sheet.
class AuditCubit extends Cubit<AuditState> {
  AuditCubit(this._repository, this._files) : super(const AuditState());

  final AuditRepository _repository;
  final AuditFileService _files;

  /// Load the stored audit rows (local-only).
  Future<void> load() async {
    emit(state.copyWith(status: AuditStatus.loading));
    try {
      final records = await _repository.getRecords();
      emit(state.copyWith(
        status: AuditStatus.loaded,
        records: records,
      ));
    } catch (e, st) {
      developer.log('AuditCubit.load failed',
          name: 'AuditCubit', error: e, stackTrace: st, level: 1000);
      emit(state.copyWith(
        status: AuditStatus.error,
        errorMessage: 'Could not load audit records.',
      ));
    }
  }

  Future<void> refresh() => load();

  /// Pick a CSV/XLSX file and validate it. On success this does NOT persist
  /// anything — it stashes the result in [AuditState.pendingImport] so the UI can
  /// show the validation summary and let the user decide. A file with a
  /// whole-file problem (empty / missing headers) surfaces as [actionError]
  /// without opening the review.
  Future<void> pickAndValidateImport() async {
    if (state.isBusy) return;
    emit(state.copyWith(isBusy: true, clearMessages: true));
    try {
      final result = await _files.pickAndParse();
      if (result == null) {
        // User cancelled the picker — nothing to do.
        emit(state.copyWith(isBusy: false));
        return;
      }
      if (result.hasFileError) {
        emit(state.copyWith(isBusy: false, actionError: result.fileError));
        return;
      }
      emit(state.copyWith(isBusy: false, pendingImport: result));
    } on AuditFileException catch (e) {
      emit(state.copyWith(isBusy: false, actionError: e.message));
    } catch (e, st) {
      developer.log('AuditCubit.pickAndValidateImport failed',
          name: 'AuditCubit', error: e, stackTrace: st, level: 1000);
      emit(state.copyWith(
        isBusy: false,
        actionError: 'Could not read the selected file.',
      ));
    }
  }

  /// Dismiss the import review without persisting anything.
  void cancelImport() => emit(state.copyWith(clearPendingImport: true));

  /// Persist the valid rows from the pending import, then reload. No-op if there
  /// is no pending import or it has no valid rows.
  Future<void> confirmImport() async {
    final pending = state.pendingImport;
    if (pending == null || !pending.hasValidRecords) return;
    emit(state.copyWith(isBusy: true, clearMessages: true));
    try {
      await _repository.importRecords(pending.validRecords);
      final records = await _repository.getRecords();
      final skipped = pending.errorCount;
      emit(state.copyWith(
        status: AuditStatus.loaded,
        records: records,
        isBusy: false,
        clearPendingImport: true,
        actionMessage: skipped == 0
            ? 'Imported ${pending.validCount} row(s).'
            : 'Imported ${pending.validCount} row(s); skipped $skipped invalid row(s).',
      ));
    } catch (e, st) {
      developer.log('AuditCubit.confirmImport failed',
          name: 'AuditCubit', error: e, stackTrace: st, level: 1000);
      emit(state.copyWith(
        isBusy: false,
        actionError: 'Could not save the imported rows.',
      ));
    }
  }

  /// Export all stored audit rows to [format] and open the share sheet.
  Future<void> exportRecords(AuditFileFormat format) async {
    if (state.isBusy) return;
    if (state.records.isEmpty) {
      emit(state.copyWith(actionError: 'There are no audit records to export.'));
      return;
    }
    emit(state.copyWith(isBusy: true, clearMessages: true));
    try {
      final name = await _files.exportRecords(state.records, format);
      emit(state.copyWith(
        isBusy: false,
        actionMessage: 'Exported ${state.records.length} row(s) to $name.',
      ));
    } catch (e, st) {
      developer.log('AuditCubit.exportRecords failed',
          name: 'AuditCubit', error: e, stackTrace: st, level: 1000);
      emit(state.copyWith(isBusy: false, actionError: 'Could not export records.'));
    }
  }

  /// Generate the sample template in [format] and open the share sheet.
  Future<void> downloadTemplate(AuditFileFormat format) async {
    if (state.isBusy) return;
    emit(state.copyWith(isBusy: true, clearMessages: true));
    try {
      final name = await _files.exportTemplate(format);
      emit(state.copyWith(isBusy: false, actionMessage: 'Saved template $name.'));
    } catch (e, st) {
      developer.log('AuditCubit.downloadTemplate failed',
          name: 'AuditCubit', error: e, stackTrace: st, level: 1000);
      emit(state.copyWith(
          isBusy: false, actionError: 'Could not create the template.'));
    }
  }

  /// Remove every stored audit row, then reload.
  Future<void> clearAll() async {
    emit(state.copyWith(isBusy: true, clearMessages: true));
    try {
      await _repository.clear();
      emit(state.copyWith(
        status: AuditStatus.loaded,
        records: const [],
        isBusy: false,
        actionMessage: 'Cleared all audit records.',
      ));
    } catch (e, st) {
      developer.log('AuditCubit.clearAll failed',
          name: 'AuditCubit', error: e, stackTrace: st, level: 1000);
      emit(state.copyWith(isBusy: false, actionError: 'Could not clear records.'));
    }
  }

  /// Called by the UI after it has shown [actionMessage]/[actionError] so the
  /// same SnackBar isn't re-shown on the next rebuild.
  void acknowledgeMessages() => emit(state.copyWith(clearMessages: true));
}
