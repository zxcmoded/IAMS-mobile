import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/inventory_record_repository.dart';
import '../../data/models/inventory_record.dart';

enum InventoryRecordsStatus { loading, loaded, error }

/// State for the offline records list — every saved [InventoryRecord] read from
/// local SQLite (no network).
class InventoryRecordsState extends Equatable {
  const InventoryRecordsState({
    this.status = InventoryRecordsStatus.loading,
    this.records = const [],
    this.errorMessage,
  });

  final InventoryRecordsStatus status;
  final List<InventoryRecord> records;
  final String? errorMessage;

  bool get isEmpty => records.isEmpty;

  @override
  List<Object?> get props => [status, records, errorMessage];
}

/// Lists locally-saved Create-Inventory records, newest first. Read-only and
/// local-only — used to prove offline persistence and to surface the "Offline"
/// badge on each record.
class InventoryRecordsCubit extends Cubit<InventoryRecordsState> {
  InventoryRecordsCubit(this._records) : super(const InventoryRecordsState());

  final InventoryRecordRepository _records;

  Future<void> load() async {
    emit(const InventoryRecordsState(status: InventoryRecordsStatus.loading));
    try {
      final records = await _records.getRecords();
      emit(InventoryRecordsState(
        status: InventoryRecordsStatus.loaded,
        records: records,
      ));
    } catch (e, st) {
      developer.log('InventoryRecordsCubit.load failed',
          name: 'InventoryRecordsCubit', error: e, stackTrace: st, level: 1000);
      emit(const InventoryRecordsState(
        status: InventoryRecordsStatus.error,
        errorMessage: 'Could not load saved inventory records.',
      ));
    }
  }

  Future<void> refresh() => load();
}
