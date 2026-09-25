/// Parses the `kitchenDisplayEnabled` field of the `public/displayControls`
/// document.
///
/// Fail-open by design: a missing document (`data == null`) or a missing
/// field both mean `true` — the display must keep working if this doc has
/// never been touched. A field that IS present but isn't a bool throws a
/// [FormatException] so the caller can surface it and then fail open.
bool parseKitchenDisplayEnabled(Map<String, dynamic>? data) {
  if (data == null) return true;
  final value = data['kitchenDisplayEnabled'];
  if (value == null) return true;
  if (value is! bool) {
    throw FormatException(
      'expected "kitchenDisplayEnabled" to be a bool, got ${value.runtimeType}',
    );
  }
  return value;
}
