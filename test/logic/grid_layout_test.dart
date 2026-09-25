import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_display/logic/grid_layout.dart';
import 'package:kitchen_display/models/kitchen_order.dart';

KitchenOrder _order(int n, {DateTime? readySince}) => KitchenOrder(
      orderNumber: n,
      items: const [OrderItem(name: 'Latte', quantity: 1)],
      readySince: readySince ?? DateTime(2026, 1, 1),
    );

void main() {
  group('gridColumnsForCount', () {
    test('0 orders -> 1 column', () {
      expect(gridColumnsForCount(0), 1);
    });
    test('1 order -> 1 column', () {
      expect(gridColumnsForCount(1), 1);
    });
    test('2 orders -> 2 columns', () {
      expect(gridColumnsForCount(2), 2);
    });
    test('4 orders -> 2 columns (boundary)', () {
      expect(gridColumnsForCount(4), 2);
    });
    test('5 orders -> 3 columns (boundary)', () {
      expect(gridColumnsForCount(5), 3);
    });
    test('6 orders -> 3 columns', () {
      expect(gridColumnsForCount(6), 3);
    });
  });

  group('gridRowsForCount', () {
    test('5 orders in 3 columns -> 2 rows', () {
      expect(gridRowsForCount(5, 3), 2);
    });
    test('6 orders in 3 columns -> 2 rows', () {
      expect(gridRowsForCount(6, 3), 2);
    });
    test('4 orders in 2 columns -> 2 rows', () {
      expect(gridRowsForCount(4, 2), 2);
    });
    test('1 order in 1 column -> 1 row', () {
      expect(gridRowsForCount(1, 1), 1);
    });
  });

  group('splitOrdersForGrid', () {
    test('exactly 6 orders -> no overflow', () {
      final orders = List.generate(6, (i) => _order(i));
      final split = splitOrdersForGrid(orders);
      expect(split.mainTiles.length, 6);
      expect(split.overflow, isEmpty);
    });

    test('exactly 7 orders -> 1 order in overflow', () {
      final orders = List.generate(7, (i) => _order(i));
      final split = splitOrdersForGrid(orders);
      expect(split.mainTiles.length, 6);
      expect(split.overflow.length, 1);
      expect(split.overflow.single.orderNumber, 6);
    });

    test('does not reorder — first 6 stay in original order', () {
      final orders = List.generate(9, (i) => _order(i));
      final split = splitOrdersForGrid(orders);
      expect(split.mainTiles.map((o) => o.orderNumber).toList(),
          [0, 1, 2, 3, 4, 5]);
      expect(split.overflow.map((o) => o.orderNumber).toList(), [6, 7, 8]);
    });
  });

  group('isLongWait', () {
    final readySince = DateTime(2026, 1, 1, 12, 0, 0);

    test('4:59 elapsed -> not flagged', () {
      final now = readySince.add(const Duration(minutes: 4, seconds: 59));
      expect(isLongWait(readySince, now), isFalse);
    });

    test('exactly 5:00 elapsed -> not flagged', () {
      final now = readySince.add(const Duration(minutes: 5));
      expect(isLongWait(readySince, now), isFalse);
    });

    test('5:01 elapsed -> flagged', () {
      final now = readySince.add(const Duration(minutes: 5, seconds: 1));
      expect(isLongWait(readySince, now), isTrue);
    });
  });
}
