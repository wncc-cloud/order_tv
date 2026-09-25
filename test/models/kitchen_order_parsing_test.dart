import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_display/models/kitchen_order.dart';

void main() {
  group('parseKitchenOrders', () {
    test('document does not exist (null data) -> empty list, no throw', () {
      expect(parseKitchenOrders(null), isEmpty);
    });

    test('document exists but is missing the orders field -> empty list', () {
      expect(parseKitchenOrders({'updatedAt': Timestamp.now()}), isEmpty);
    });

    test('well-formed document parses correctly', () {
      final readySince = Timestamp.fromDate(DateTime(2026, 1, 1, 12, 0, 0));
      final orders = parseKitchenOrders({
        'orders': [
          {
            'orderNumber': 42,
            'items': [
              {'name': 'Latte', 'quantity': 2},
              {'name': 'Croissant', 'quantity': 1},
            ],
            'readySince': readySince,
          },
        ],
        'updatedAt': Timestamp.now(),
      });

      expect(orders, hasLength(1));
      expect(orders.single.orderNumber, 42);
      expect(orders.single.readySince, readySince.toDate());
      expect(orders.single.items, hasLength(2));
      expect(orders.single.items[0].name, 'Latte');
      expect(orders.single.items[0].quantity, 2);
    });

    test('malformed shape (orders is not a list) throws FormatException', () {
      expect(
        () => parseKitchenOrders({'orders': 'not a list'}),
        throwsFormatException,
      );
    });

    test('malformed shape (wrong type for orderNumber) throws FormatException', () {
      expect(
        () => parseKitchenOrders({
          'orders': [
            {
              'orderNumber': 'not an int',
              'items': <Map<String, dynamic>>[],
              'readySince': Timestamp.now(),
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('malformed shape (readySince not a Timestamp) throws FormatException', () {
      expect(
        () => parseKitchenOrders({
          'orders': [
            {
              'orderNumber': 1,
              'items': <Map<String, dynamic>>[],
              'readySince': '2026-01-01',
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
