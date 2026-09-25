# TV Stuck-Display Fix Plan

**Status:** proposed, not implemented.
**Problem:** the kitchen TV (`oder_tv`, Android TV kiosk) sometimes gets stuck showing a
stale/already-delivered order, and stays stuck even after internet connectivity is
confirmed restored. A prior fix (2026-09-16, shipped in `1.0.3+4`/now `1.0.4+5`) added a
3-minute unconditional resubscribe of the Firestore listeners
(`kHeartbeatResubscribeInterval` in `lib/services/kitchen_firestore_service.dart`), but
the issue is still occurring, which means resubscribing the *listener* alone isn't always
enough to recover.

**Likely cause:** Firestore's Dart SDK multiplexes listeners over one shared gRPC
connection. Cancelling and re-adding a listener re-registers the callback, but if the
underlying connection itself is wedged, a fresh listener on the same connection can still
receive nothing — which would explain "stuck even though the internet is back."

## Plan

### 1. Force a real network reconnect, not just a listener resubscribe
Extend the existing heartbeat in `kitchen_firestore_service.dart` to call
`FirebaseFirestore.instance.disableNetwork()` then `enableNetwork()` before
resubscribing, forcing a transport-level reconnect instead of just re-attaching a
callback to a possibly-dead connection.

```dart
_kitchenHeartbeatTimer = Timer.periodic(kHeartbeatResubscribeInterval, (_) async {
  if (_disposed) return;
  _kitchenRetryTimer?.cancel();
  _kitchenBackoffIndex = 0;
  await _firestore.disableNetwork();
  await _firestore.enableNetwork();
  _subscribeKitchen(onData, onStreamError, onParseError);
});
```

Since `_firestore` is one shared instance used by both `listenKitchenDisplay` and
`listenDisplayControls`, this toggle should happen once in a shared heartbeat, not
duplicated per listener (or it fires twice back-to-back).

**Risk:** low — Firestore's own documented API for exactly this. Test: turn on airplane
mode on the device, wait past one heartbeat interval, turn it back on, confirm the
display updates without manual intervention.

### 2. Staleness watchdog → full app restart as the safety net
Track the timestamp of the last successfully received snapshot. If it's older than a
threshold (e.g. 8 minutes) *and* the device reports it has connectivity, force a full
process restart — this re-initializes the Firebase SDK from scratch and recovers from
anything wedged in-process that step 1 doesn't catch.

```dart
// KitchenFirestoreService
DateTime? lastSnapshotAt;
// set in _subscribeKitchen's onData callback

// _KitchenDisplayScreenState, alongside the existing 1s _ticker
_ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
  if (!mounted) return;
  setState(() {});
  final last = _service.lastSnapshotAt;
  final stale = last != null &&
      DateTime.now().difference(last) > const Duration(minutes: 8);
  if (stale && await Connectivity().checkConnectivity() != ConnectivityResult.none) {
    Restart.restartApp(); // package: restart_app
  }
});
```

Add `connectivity_plus` and `restart_app` (or a small platform channel calling
`Activity.recreate()`) to `pubspec.yaml`.

**Risk:** low-medium — a restart causes a ~2-3s black screen, acceptable for an
always-on kitchen display; needs testing that `restart_app` behaves correctly on the
specific Android TV box hardware in use (some restart plugins behave inconsistently
across OEM TV launchers).

### 3. Manual hard-refresh for staff (software restart via remote, not a hardware reset)
A remote-control long-press (e.g. hold OK/center for 3s) triggers the same
`Restart.restartApp()` used in step 2, giving staff an immediate unstick option without
walking to the box or pulling power. No visible on-screen button, consistent with the
screen's existing "no buttons, no touch targets" design — document the gesture for staff
on a small physical note near the TV instead.

```dart
bool _onKey(KeyEvent event) {
  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.select) {
    _longPressTimer ??= Timer(const Duration(seconds: 3), () => Restart.restartApp());
  }
  if (event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.select) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }
  return false;
}
```

**Risk:** low — additive, no effect on normal operation; needs a quick check that the
Android TV remote's OK/center button maps to `LogicalKeyboardKey.select` on the actual
hardware in use.

### 4. Field telemetry (do this first)
Right now there is no visibility into what a stuck device is actually doing —
`onStreamError`/`onParseError` in `kitchen_display_screen.dart` are empty handlers, and
nothing records device state anywhere. Before trusting steps 1-3 fixed anything, add a
lightweight heartbeat write so a stuck device leaves a trace:

```dart
_kitchenHeartbeatTimer = Timer.periodic(kHeartbeatResubscribeInterval, (_) async {
  if (_disposed) return;
  try {
    await _firestore.doc('businesses/$kBusinessId/devices/$deviceId').set({
      'lastHeartbeatAt': FieldValue.serverTimestamp(),
      'lastSnapshotAt': lastSnapshotAt,
    }, SetOptions(merge: true));
  } catch (_) {}
  // ...existing resubscribe logic
});
```

`deviceId`: a stable per-install UUID generated once and cached in
`shared_preferences`. No dashboard needed initially — next time a TV is stuck, read
that Firestore doc directly to see whether the device thinks it's still receiving data
(points at a UI/data bug) or knows it's stalled and isn't recovering (points at steps
1-2 being insufficient).

**Risk:** near zero — additive write, doesn't change any existing behavior.

## Recommended order

1. **Step 4** first — telemetry, cheap, unlocks real diagnosis instead of guessing.
2. **Step 1** — the likely actual root-cause fix (network toggle vs. listener-only
   resubscribe).
3. **Step 2** — unconditional safety net in case step 1's theory is wrong.
4. **Step 3** — low-cost staff-facing escape hatch, ship alongside step 2 since it
   reuses the same `restart_app` mechanism.

## Open questions for the café owner
- Is this always the same physical TV box, or does it rotate between devices? (Memory
  from the 09-16 incident: it was device-local, not both TVs at once — worth
  re-confirming it's still that pattern before assuming steps 1-2 are the whole fix.)
- Any pattern to when it happens (time of day, after wifi AP restarts, box model)?
- OK to ship a ~2-3s black-screen restart during service hours if the watchdog trips?

## Deploy process (once implemented)
See existing reference: build/version-bump/test/`flutter build apk --release`/
`firebase appdistribution:distribute` to `why-not-cafe-prod`, app id
`1:871637263829:android:a36f6ca96849181a5c495c`, tester
`whynotcafe.expenses@gmail.com`.
