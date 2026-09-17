import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/core/network/problem_details.dart';
import 'package:iams_mobile/features/inventory/data/models/stock_conflict.dart';

void main() {
  test('stock_version_conflict keeps conflicts[] in extensions', () {
    final ex = ProblemDetailsParser.parse(
      statusCode: 409,
      data: {
        'title': 'Conflict',
        'status': 409,
        'code': 'stock_version_conflict',
        'conflicts': [
          {
            'binId': 'b1',
            'expectedVersion': 0,
            'currentVersion': 3,
            'currentQuantityOnHand': 12.0,
          }
        ],
      },
    );

    expect(ex.code, ApiErrorCode.stockVersionConflict);
    expect(ex.isStockVersionConflict, isTrue);
    final conflicts = StockConflict.listFrom(ex.extensions['conflicts']);
    expect(conflicts.single.currentVersion, 3);
    expect(conflicts.single.currentQuantityOnHand, 12.0);
    // Standard members are NOT duplicated into extensions.
    expect(ex.extensions.containsKey('title'), isFalse);
    expect(ex.extensions.containsKey('code'), isFalse);
  });

  test('insufficient_stock keeps binId + availableQuantity in extensions', () {
    final ex = ProblemDetailsParser.parse(
      statusCode: 422,
      data: {
        'title': 'Insufficient',
        'code': 'insufficient_stock',
        'binId': 'b9',
        'availableQuantity': 3.0,
      },
    );

    expect(ex.isInsufficientStock, isTrue);
    expect(ex.extensions['binId'], 'b9');
    expect(ex.extensions['availableQuantity'], 3.0);
  });

  test('a body with no extensions yields an empty extensions map', () {
    final ex = ProblemDetailsParser.parse(
      statusCode: 404,
      data: {'title': 'Not found', 'code': 'not_found'},
    );
    expect(ex.extensions, isEmpty);
  });
}
