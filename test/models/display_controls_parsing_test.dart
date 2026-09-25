import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_display/models/display_controls.dart';

void main() {
  group('parseKitchenDisplayEnabled', () {
    test('document does not exist (null data) -> true (fail-open)', () {
      expect(parseKitchenDisplayEnabled(null), isTrue);
    });

    test('document exists but field missing -> true (fail-open)', () {
      expect(parseKitchenDisplayEnabled(<String, dynamic>{}), isTrue);
    });

    test('field explicitly true -> true', () {
      expect(parseKitchenDisplayEnabled({'kitchenDisplayEnabled': true}), isTrue);
    });

    test('field explicitly false -> false', () {
      expect(parseKitchenDisplayEnabled({'kitchenDisplayEnabled': false}), isFalse);
    });

    test('wrong type for field throws FormatException', () {
      expect(
        () => parseKitchenDisplayEnabled({'kitchenDisplayEnabled': 'yes'}),
        throwsFormatException,
      );
    });
  });
}
