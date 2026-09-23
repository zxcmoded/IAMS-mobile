import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/util/uuid.dart';
import '../../../access/presentation/controller/selected_location_controller.dart';
import '../../../masterdata/data/hierarchy_repository.dart';
import '../../../masterdata/data/models/bin.dart';
import '../../../masterdata/data/models/rack.dart';
import '../../../masterdata/data/models/warehouse.dart';
import '../../data/inventory_record_repository.dart';
import '../../data/inventory_repository.dart';
import '../../data/models/inventory_record.dart';

/// Guard window for accidental double-fires of a *single physical scan*. Two
/// scans of the **same** code within this window collapse to one increment; the
/// window is deliberately well under the spec's ~0.5s continuous-scan interval
/// (500ms) so legitimate repeat scans of the same SKU — each a real quantity
/// increment — are never dropped. See the progress-file note on this nuance.
const Duration kScanDebounceWindow = Duration(milliseconds: 250);

enum SaveStatus { idle, saving, saved, error }

/// State for the offline-first Create-Inventory flow. Every list/validation
/// field is sourced from local SQLite; there are no network calls anywhere in
/// this flow.
class CreateInventoryState extends Equatable {
  const CreateInventoryState({
    this.warehouse,
    this.warehouseError,
    this.racks = const [],
    this.selectedRackId,
    this.bins = const [],
    this.selectedBinId,
    this.lines = const [],
    this.skuError,
    this.lastAddedItemId,
    this.saveStatus = SaveStatus.idle,
    this.saveError,
    this.savedRecordId,
  });

  /// The validated warehouse (in the current location), or `null` until a valid
  /// warehouse code is entered/scanned.
  final Warehouse? warehouse;
  final String? warehouseError;

  final List<Rack> racks;
  final String? selectedRackId;

  final List<Bin> bins;
  final String? selectedBinId;

  final List<InventoryRecordLine> lines;
  final String? skuError;

  /// The item id of the most recently added/incremented line — lets the UI flash
  /// or scroll to it. Transient (cleared on the next mutation that doesn't set
  /// it).
  final String? lastAddedItemId;

  final SaveStatus saveStatus;
  final String? saveError;
  final String? savedRecordId;

  bool get hasWarehouse => warehouse != null;

  /// A record needs a valid warehouse and at least one SKU line to save.
  bool get canSave =>
      warehouse != null && lines.isNotEmpty && saveStatus != SaveStatus.saving;

  double get totalQuantity =>
      lines.fold<double>(0, (sum, l) => sum + l.quantity);

  CreateInventoryState copyWith({
    Warehouse? warehouse,
    bool clearWarehouse = false,
    String? warehouseError,
    bool clearWarehouseError = false,
    List<Rack>? racks,
    String? selectedRackId,
    bool clearRack = false,
    List<Bin>? bins,
    String? selectedBinId,
    bool clearBin = false,
    List<InventoryRecordLine>? lines,
    String? skuError,
    bool clearSkuError = false,
    String? lastAddedItemId,
    bool clearLastAdded = false,
    SaveStatus? saveStatus,
    String? saveError,
    bool clearSaveError = false,
    String? savedRecordId,
  }) =>
      CreateInventoryState(
        warehouse: clearWarehouse ? null : (warehouse ?? this.warehouse),
        warehouseError:
            clearWarehouseError ? null : (warehouseError ?? this.warehouseError),
        racks: racks ?? this.racks,
        selectedRackId:
            clearRack ? null : (selectedRackId ?? this.selectedRackId),
        bins: bins ?? this.bins,
        selectedBinId: clearBin ? null : (selectedBinId ?? this.selectedBinId),
        lines: lines ?? this.lines,
        skuError: clearSkuError ? null : (skuError ?? this.skuError),
        lastAddedItemId:
            clearLastAdded ? null : (lastAddedItemId ?? this.lastAddedItemId),
        saveStatus: saveStatus ?? this.saveStatus,
        saveError: clearSaveError ? null : (saveError ?? this.saveError),
        savedRecordId: savedRecordId ?? this.savedRecordId,
      );

  @override
  List<Object?> get props => [
        warehouse,
        warehouseError,
        racks,
        selectedRackId,
        bins,
        selectedBinId,
        lines,
        skuError,
        lastAddedItemId,
        saveStatus,
        saveError,
        savedRecordId,
      ];
}

/// Drives the offline-first Create-Inventory flow entirely against local SQLite:
///
/// * Warehouse (required) — validate a scanned/entered code against the
///   warehouses of the user's current location; on success load the related
///   racks.
/// * Rack (optional) — a dropdown scoped to the warehouse; selecting one loads
///   its bins.
/// * Bin (optional) — a dropdown scoped to the rack.
/// * SKU (required, repeatable) — validate against the local `inventory_item`
///   cache; repeated scans of the same SKU accumulate onto one line (with a
///   short double-fire guard). Lines are editable/removable before save.
/// * Save — persists an [InventoryRecord] with `isOffline = true` (never
///   flipped by this code).
class CreateInventoryCubit extends Cubit<CreateInventoryState> {
  CreateInventoryCubit({
    required HierarchyRepository hierarchy,
    required InventoryRepository inventory,
    required InventoryRecordRepository records,
    required SelectedLocationController selectedLocation,
    DateTime Function()? clock,
  })  : _hierarchy = hierarchy,
        _inventory = inventory,
        _records = records,
        _selectedLocation = selectedLocation,
        _clock = clock ?? DateTime.now,
        super(const CreateInventoryState());

  // ignore_for_file: prefer_initializing_formals
  // ^ the deps below are assigned from named params (not `this._x` initializing
  //   formals) purely so DI call sites read as `hierarchy:` etc. — same style as
  //   DashboardCubit.

  final HierarchyRepository _hierarchy;
  final InventoryRepository _inventory;
  final InventoryRecordRepository _records;
  final SelectedLocationController _selectedLocation;
  final DateTime Function() _clock;

  // Double-fire guard bookkeeping (last accepted scan of a code + its time).
  String? _lastScanCode;
  DateTime? _lastScanAt;

  // ---- Warehouse ------------------------------------------------------------

  /// Validate a scanned/entered warehouse code against the warehouses assigned
  /// to the user's current location. On success, adopt the warehouse and load
  /// its racks; on failure, surface an error and clear any prior selection.
  ///
  /// The code is matched (case-insensitive) against the warehouse **name** —
  /// the codebase carries no separate warehouse barcode/code field locally.
  Future<void> validateWarehouse(String code) async {
    final term = code.trim();
    if (term.isEmpty) {
      emit(state.copyWith(warehouseError: 'Enter or scan a warehouse code.'));
      return;
    }
    final locationId = _selectedLocation.currentLocationId;
    if (locationId == null) {
      emit(state.copyWith(
        warehouseError: 'No current location selected.',
      ));
      return;
    }
    try {
      final warehouses = await _hierarchy.getWarehouses(locationId);
      Warehouse? match;
      for (final w in warehouses) {
        if (w.name.toLowerCase() == term.toLowerCase()) {
          match = w;
          break;
        }
      }
      if (match == null) {
        // Reset everything downstream so a failed re-entry can't keep a stale
        // warehouse/rack/bin around.
        emit(state.copyWith(
          clearWarehouse: true,
          warehouseError:
              'Warehouse "$term" is not in your current location.',
          racks: const [],
          clearRack: true,
          bins: const [],
          clearBin: true,
        ));
        return;
      }
      final racks = await _hierarchy.getRacks(match.id);
      emit(state.copyWith(
        warehouse: match,
        clearWarehouseError: true,
        racks: racks,
        clearRack: true,
        bins: const [],
        clearBin: true,
      ));
    } catch (e, st) {
      developer.log('validateWarehouse failed',
          name: 'CreateInventoryCubit', error: e, stackTrace: st, level: 1000);
      emit(state.copyWith(
        warehouseError: 'Could not validate the warehouse. Please try again.',
      ));
    }
  }

  // ---- Rack / Bin -----------------------------------------------------------

  /// Select (or clear, with `null`) the optional rack. Selecting a rack loads
  /// its bins; clearing it (or picking a different rack) resets the bin.
  Future<void> selectRack(String? rackId) async {
    if (rackId == null) {
      emit(state.copyWith(clearRack: true, bins: const [], clearBin: true));
      return;
    }
    final bins = await _hierarchy.getBins(rackId);
    emit(state.copyWith(
      selectedRackId: rackId,
      bins: bins,
      clearBin: true,
    ));
  }

  /// Select (or clear, with `null`) the optional bin.
  void selectBin(String? binId) {
    if (binId == null) {
      emit(state.copyWith(clearBin: true));
      return;
    }
    emit(state.copyWith(selectedBinId: binId));
  }

  // ---- SKU lines ------------------------------------------------------------

  /// A **continuous scan** of a SKU/barcode — increments the SKU's line by one.
  /// A repeat scan of the *same* code within [kScanDebounceWindow] is treated as
  /// an accidental double-fire of one physical label and ignored; anything at or
  /// beyond that window (e.g. the spec's ~0.5s deliberate re-scans) accumulates.
  Future<void> scanSku(String code) async {
    final term = code.trim();
    if (term.isEmpty) return;

    final now = _clock();
    final isDoubleFire = _lastScanCode != null &&
        _lastScanCode!.toLowerCase() == term.toLowerCase() &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < kScanDebounceWindow;
    // Advance the guard timestamp on every scan attempt so a rapid burst is
    // collapsed against the most recent fire, not just the first.
    _lastScanCode = term;
    _lastScanAt = now;
    if (isDoubleFire) return;

    await _resolveAndAccumulate(term, 1);
  }

  /// Manually add a SKU with an explicit [quantity] (defaults to 1). No
  /// double-fire guard — a manual entry is always a deliberate action.
  Future<void> addSkuManual(String code, {double quantity = 1}) async {
    final term = code.trim();
    if (term.isEmpty) {
      emit(state.copyWith(skuError: 'Enter or scan a SKU.'));
      return;
    }
    if (quantity <= 0) {
      emit(state.copyWith(skuError: 'Quantity must be greater than zero.'));
      return;
    }
    await _resolveAndAccumulate(term, quantity);
  }

  Future<void> _resolveAndAccumulate(String code, double delta) async {
    final item = await _inventory.findItemByCode(code);
    if (item == null) {
      emit(state.copyWith(
        skuError: 'SKU "$code" is not in your local inventory.',
        clearLastAdded: true,
      ));
      return;
    }

    final lines = [...state.lines];
    final idx = lines.indexWhere((l) => l.inventoryItemId == item.id);
    if (idx >= 0) {
      lines[idx] = lines[idx].copyWith(quantity: lines[idx].quantity + delta);
    } else {
      lines.add(InventoryRecordLine(
        inventoryItemId: item.id,
        sku: item.sku,
        name: item.name,
        quantity: delta,
      ));
    }
    emit(state.copyWith(
      lines: lines,
      clearSkuError: true,
      lastAddedItemId: item.id,
    ));
  }

  /// Set an existing line's quantity outright (inline edit). A quantity of zero
  /// or less removes the line.
  void setLineQuantity(String inventoryItemId, double quantity) {
    if (quantity <= 0) {
      removeLine(inventoryItemId);
      return;
    }
    final lines = state.lines
        .map((l) => l.inventoryItemId == inventoryItemId
            ? l.copyWith(quantity: quantity)
            : l)
        .toList(growable: false);
    emit(state.copyWith(lines: lines, clearLastAdded: true));
  }

  /// Remove a SKU line before saving.
  void removeLine(String inventoryItemId) {
    final lines = state.lines
        .where((l) => l.inventoryItemId != inventoryItemId)
        .toList(growable: false);
    emit(state.copyWith(lines: lines, clearLastAdded: true));
  }

  void clearSkuError() => emit(state.copyWith(clearSkuError: true));

  // ---- Save -----------------------------------------------------------------

  /// Persist the in-progress draft as a new offline record. The record is always
  /// stamped `isOffline = true`; this code never sets it to `false`.
  Future<void> save() async {
    if (!state.canSave) return;
    emit(state.copyWith(saveStatus: SaveStatus.saving, clearSaveError: true));

    final warehouse = state.warehouse!;
    final rack = state.selectedRackId == null
        ? null
        : _firstWhereOrNull(state.racks, state.selectedRackId!);
    final bin = state.selectedBinId == null
        ? null
        : _firstBinOrNull(state.bins, state.selectedBinId!);
    final now = _clock().toUtc();

    final record = InventoryRecord(
      id: newUuidV4(),
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      rackId: rack?.id,
      rackName: rack?.name,
      binId: bin?.id,
      binName: bin?.name,
      items: state.lines,
      isOffline: true, // never flipped to false by this code
      createdAtUtc: now,
    );

    try {
      await _records.create(record);
      emit(state.copyWith(
        saveStatus: SaveStatus.saved,
        savedRecordId: record.id,
      ));
    } catch (e, st) {
      developer.log('save inventory record failed',
          name: 'CreateInventoryCubit', error: e, stackTrace: st, level: 1000);
      emit(state.copyWith(
        saveStatus: SaveStatus.error,
        saveError: 'Could not save the inventory record. Please try again.',
      ));
    }
  }

  Rack? _firstWhereOrNull(List<Rack> racks, String id) {
    for (final r in racks) {
      if (r.id == id) return r;
    }
    return null;
  }

  Bin? _firstBinOrNull(List<Bin> bins, String id) {
    for (final b in bins) {
      if (b.id == id) return b;
    }
    return null;
  }
}
