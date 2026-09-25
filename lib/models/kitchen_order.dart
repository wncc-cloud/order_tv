import 'package:cloud_firestore/cloud_firestore.dart';

class OrderItem {
  const OrderItem({required this.name, required this.quantity});

  final String name;
  final int quantity;

  @override
  String toString() => '$name × $quantity';
}

class KitchenOrder {
  const KitchenOrder({
    required this.orderNumber,
    required this.items,
    required this.readySince,
  });

  final int orderNumber;
  final List<OrderItem> items;
  final DateTime readySince;
}

/// Parses the `orders` field of the `public/kitchenDisplay` document.
///
/// A missing document (`data == null`) or a missing `orders` field both mean
/// an empty list — this never throws for those two cases. A field that IS
/// present but has the wrong shape (wrong types, non-list, malformed order
/// entries) throws a [FormatException] so the caller can surface exactly
/// what was wrong instead of silently rendering nothing.
List<KitchenOrder> parseKitchenOrders(Map<String, dynamic>? data) {
  if (data == null) return const [];
  final rawOrders = data['orders'];
  if (rawOrders == null) return const [];
  if (rawOrders is! List) {
    throw FormatException(
      'expected "orders" to be a list, got ${rawOrders.runtimeType}',
    );
  }

  return rawOrders.map((raw) {
    if (raw is! Map) {
      throw FormatException('expected an order to be a map, got ${raw.runtimeType}');
    }
    final map = Map<String, dynamic>.from(raw);

    final orderNumber = map['orderNumber'];
    if (orderNumber is! int) {
      throw FormatException(
        'expected "orderNumber" to be an int, got ${orderNumber.runtimeType}',
      );
    }

    final rawItems = map['items'];
    if (rawItems is! List) {
      throw FormatException(
        'expected "items" to be a list, got ${rawItems.runtimeType}',
      );
    }
    final items = rawItems.map((rawItem) {
      if (rawItem is! Map) {
        throw FormatException('expected an item to be a map, got ${rawItem.runtimeType}');
      }
      final itemMap = Map<String, dynamic>.from(rawItem);
      final name = itemMap['name'];
      final quantity = itemMap['quantity'];
      if (name is! String) {
        throw FormatException('expected item "name" to be a string, got ${name.runtimeType}');
      }
      if (quantity is! int) {
        throw FormatException(
          'expected item "quantity" to be an int, got ${quantity.runtimeType}',
        );
      }
      return OrderItem(name: name, quantity: quantity);
    }).toList();

    final readySince = map['readySince'];
    if (readySince is! Timestamp) {
      throw FormatException(
        'expected "readySince" to be a Timestamp, got ${readySince.runtimeType}',
      );
    }

    return KitchenOrder(
      orderNumber: orderNumber,
      items: items,
      readySince: readySince.toDate(),
    );
  }).toList();
}
