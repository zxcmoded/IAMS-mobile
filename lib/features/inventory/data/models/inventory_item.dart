import 'package:equatable/equatable.dart';

/// One row of the F4 inventory list (`GET /api/inventory/items`).
/// `totalQuantityOnHand` is the sum across all of the item's bins — the value
/// the list filter pills act on.
class InventoryItem extends Equatable {
  const InventoryItem({
    required this.id,
    required this.sku,
    required this.name,
    required this.isActive,
    required this.totalQuantityOnHand,
    this.barcode,
    this.unitOfMeasure,
    this.category,
  });

  final String id;
  final String sku;
  final String name;
  final bool isActive;
  final double totalQuantityOnHand;
  final String? barcode;
  final String? unitOfMeasure;
  final String? category;

  bool get isOutOfStock => totalQuantityOnHand <= 0;

  InventoryItem copyWith({double? totalQuantityOnHand}) => InventoryItem(
        id: id,
        sku: sku,
        name: name,
        isActive: isActive,
        totalQuantityOnHand: totalQuantityOnHand ?? this.totalQuantityOnHand,
        barcode: barcode,
        unitOfMeasure: unitOfMeasure,
        category: category,
      );

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        id: json['id'] as String,
        sku: json['sku'] as String,
        name: json['name'] as String,
        isActive: json['isActive'] as bool? ?? true,
        totalQuantityOnHand:
            (json['totalQuantityOnHand'] as num?)?.toDouble() ?? 0,
        barcode: json['barcode'] as String?,
        unitOfMeasure: json['unitOfMeasure'] as String?,
        category: json['category'] as String?,
      );

  @override
  List<Object?> get props => [
        id,
        sku,
        name,
        isActive,
        totalQuantityOnHand,
        barcode,
        unitOfMeasure,
        category,
      ];
}

/// A page of the offset-paginated inventory list. `hasMore` is the server's
/// peek-ahead signal (no separate COUNT).
class InventoryPage extends Equatable {
  const InventoryPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  final List<InventoryItem> items;
  final int page;
  final int pageSize;
  final bool hasMore;

  factory InventoryPage.fromJson(Map<String, dynamic> json) => InventoryPage(
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        page: json['page'] as int? ?? 1,
        pageSize: json['pageSize'] as int? ?? 50,
        hasMore: json['hasMore'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [items, page, pageSize, hasMore];
}
