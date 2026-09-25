import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/display_controls.dart';
import '../models/kitchen_order.dart';

const String kBusinessId = 'why-not-cafe';

/// Capped exponential backoff (seconds) used to resubscribe after a stream
/// hits a terminal error (e.g. `permission-denied`) that Firestore's own
/// transient-network reconnection logic will never recover from on its own.
/// Resets back to the front of this list once a snapshot actually succeeds.
const List<int> kReconnectBackoffSeconds = [2, 4, 8, 16, 32, 60];

/// How often both listeners are force-torn-down and resubscribed from
/// scratch, independent of whether either has ever errored, and how often a
/// heartbeat/telemetry doc is written. This exists for a failure mode the
/// error-driven backoff above can't see: a silent stream stall (the
/// underlying connection dies without Firestore ever calling `onError`) has
/// been observed in the field on some Android TV boxes — one device stuck
/// showing stale orders while an identical device next to it, on the same
/// APK and same document, kept updating fine. A periodic unconditional
/// resubscribe bounds how long any single device can stay stuck, regardless
/// of the specific cause, without depending on an error callback that may
/// never fire.
const Duration kHeartbeatResubscribeInterval = Duration(minutes: 3);

/// Bound on how long a single heartbeat's Firestore calls are allowed to
/// hang before being abandoned. Without this, a wedged connection could make
/// `disableNetwork()`/`enableNetwork()`/the telemetry write themselves hang
/// forever — and since `Timer.periodic` doesn't wait for the previous tick
/// to finish, an unbounded hang plus the `_heartbeatRunning` reentrancy guard
/// below would permanently stop all future heartbeats instead of just
/// skipping one.
const Duration _kHeartbeatCallTimeout = Duration(seconds: 10);

/// Wraps the two `.snapshots()` listeners this screen needs, with automatic
/// resubscription (capped backoff) on terminal stream errors. Firestore's
/// SDK already transparently rides out transient blips (wifi drop, brief
/// server unavailability) without ever calling `onError` — but a silent
/// stall (no error, no more data, ever) is a real failure mode too. On top
/// of that, a single shared heartbeat timer periodically:
///  - forces a transport-level reconnect (`disableNetwork`/`enableNetwork`),
///    since re-adding a listener alone re-registers the callback but not the
///    underlying gRPC connection, which is the thing that's actually been
///    observed wedged in the field;
///  - force-resubscribes both listeners regardless of error state;
///  - writes a best-effort telemetry doc so a stuck device leaves a trace.
class KitchenFirestoreService {
  KitchenFirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _kitchenSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _controlsSub;
  Timer? _kitchenRetryTimer;
  Timer? _controlsRetryTimer;
  Timer? _heartbeatTimer;
  int _kitchenBackoffIndex = 0;
  int _controlsBackoffIndex = 0;
  bool _disposed = false;
  bool _heartbeatRunning = false;

  void Function(List<KitchenOrder> orders, bool exists)? _kitchenOnData;
  void Function(Object error)? _kitchenOnStreamError;
  void Function(Object error)? _kitchenOnParseError;

  void Function(bool enabled, bool exists)? _controlsOnData;
  void Function(Object error)? _controlsOnStreamError;
  void Function(Object error)? _controlsOnParseError;

  /// Timestamp of the last snapshot received on either listener (successful
  /// parse or not — a parse error still means the connection is alive).
  /// `null` until the first snapshot ever arrives. Read by the screen's
  /// staleness watchdog.
  DateTime? lastSnapshotAt;

  /// Timestamp/message of the most recent stream or parse error, kept for
  /// telemetry only (cleared on nothing — this is a "last seen" marker, not
  /// a current-error flag).
  DateTime? lastErrorAt;
  String? lastError;

  void listenKitchenDisplay({
    required void Function(List<KitchenOrder> orders, bool exists) onData,
    required void Function(Object error) onStreamError,
    required void Function(Object error) onParseError,
  }) {
    _kitchenOnData = onData;
    _kitchenOnStreamError = onStreamError;
    _kitchenOnParseError = onParseError;
    _subscribeKitchen(onData, onStreamError, onParseError);
  }

  void _subscribeKitchen(
    void Function(List<KitchenOrder> orders, bool exists) onData,
    void Function(Object error) onStreamError,
    void Function(Object error) onParseError,
  ) {
    _kitchenSub?.cancel();
    _kitchenSub = _firestore
        .doc('businesses/$kBusinessId/public/kitchenDisplay')
        .snapshots(includeMetadataChanges: true)
        .listen(
      (snapshot) {
        _kitchenBackoffIndex = 0;
        // A resubscribe (the heartbeat forces one every 3 minutes) always
        // replays the locally cached snapshot immediately, even if the
        // underlying connection is fully wedged and no server round-trip
        // ever succeeds. Only counting server-confirmed snapshots here is
        // what lets the screen's staleness watchdog actually detect a truly
        // dead connection instead of being fooled by that cache replay.
        if (!snapshot.metadata.isFromCache) {
          lastSnapshotAt = DateTime.now();
        }
        try {
          final orders = parseKitchenOrders(snapshot.data());
          onData(orders, snapshot.exists);
        } catch (e) {
          lastErrorAt = DateTime.now();
          lastError = 'kitchen parse: $e';
          onParseError(e);
          onData(const [], snapshot.exists);
        }
      },
      onError: (Object error) {
        lastErrorAt = DateTime.now();
        lastError = 'kitchen stream: $error';
        onStreamError(error);
        _scheduleKitchenResubscribe(onData, onStreamError, onParseError);
      },
    );
  }

  void _scheduleKitchenResubscribe(
    void Function(List<KitchenOrder> orders, bool exists) onData,
    void Function(Object error) onStreamError,
    void Function(Object error) onParseError,
  ) {
    if (_disposed) return;
    final delaySeconds = kReconnectBackoffSeconds[
        _kitchenBackoffIndex.clamp(0, kReconnectBackoffSeconds.length - 1)];
    _kitchenBackoffIndex++;
    _kitchenRetryTimer?.cancel();
    _kitchenRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_disposed) return;
      _subscribeKitchen(onData, onStreamError, onParseError);
    });
  }

  void listenDisplayControls({
    required void Function(bool enabled, bool exists) onData,
    required void Function(Object error) onStreamError,
    required void Function(Object error) onParseError,
  }) {
    _controlsOnData = onData;
    _controlsOnStreamError = onStreamError;
    _controlsOnParseError = onParseError;
    _subscribeControls(onData, onStreamError, onParseError);
  }

  void _subscribeControls(
    void Function(bool enabled, bool exists) onData,
    void Function(Object error) onStreamError,
    void Function(Object error) onParseError,
  ) {
    _controlsSub?.cancel();
    _controlsSub = _firestore
        .doc('businesses/$kBusinessId/public/displayControls')
        .snapshots(includeMetadataChanges: true)
        .listen(
      (snapshot) {
        _controlsBackoffIndex = 0;
        if (!snapshot.metadata.isFromCache) {
          lastSnapshotAt = DateTime.now();
        }
        try {
          final enabled = parseKitchenDisplayEnabled(snapshot.data());
          onData(enabled, snapshot.exists);
        } catch (e) {
          lastErrorAt = DateTime.now();
          lastError = 'controls parse: $e';
          onParseError(e);
          onData(true, snapshot.exists);
        }
      },
      onError: (Object error) {
        lastErrorAt = DateTime.now();
        lastError = 'controls stream: $error';
        onStreamError(error);
        _scheduleControlsResubscribe(onData, onStreamError, onParseError);
      },
    );
  }

  void _scheduleControlsResubscribe(
    void Function(bool enabled, bool exists) onData,
    void Function(Object error) onStreamError,
    void Function(Object error) onParseError,
  ) {
    if (_disposed) return;
    final delaySeconds = kReconnectBackoffSeconds[
        _controlsBackoffIndex.clamp(0, kReconnectBackoffSeconds.length - 1)];
    _controlsBackoffIndex++;
    _controlsRetryTimer?.cancel();
    _controlsRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_disposed) return;
      _subscribeControls(onData, onStreamError, onParseError);
    });
  }

  /// Starts the single shared heartbeat. Must be called after both
  /// [listenKitchenDisplay] and [listenDisplayControls] (or heartbeat ticks
  /// will just skip resubscribing whichever isn't registered yet). Safe to
  /// call more than once — it replaces any existing heartbeat timer rather
  /// than stacking a second one.
  void startHeartbeat({required String deviceId}) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(kHeartbeatResubscribeInterval, (_) {
      unawaited(_runHeartbeat(deviceId));
    });
  }

  Future<void> _runHeartbeat(String deviceId) async {
    // Reentrancy guard: if a previous tick is still awaiting a wedged
    // network call when the next tick fires, skip instead of stacking a
    // second concurrent disableNetwork/enableNetwork/resubscribe cycle.
    if (_disposed || _heartbeatRunning) return;
    _heartbeatRunning = true;
    try {
      try {
        await _firestore
            .doc('businesses/$kBusinessId/devices/$deviceId')
            .set({
          'lastHeartbeatAt': FieldValue.serverTimestamp(),
          'lastSnapshotAt': lastSnapshotAt,
          'lastErrorAt': lastErrorAt,
          'lastError': lastError,
        }, SetOptions(merge: true)).timeout(_kHeartbeatCallTimeout);
      } catch (e) {
        // Telemetry is best-effort — a permission or timeout failure here
        // must never block the reconnect/resubscribe below. Logged (not
        // swallowed silently) so a missing Firestore security rule for this
        // path shows up as "permission-denied" in `adb logcat` instead of
        // just... nothing ever appearing in the devices/ collection.
        debugPrint('kitchen telemetry write failed: $e');
      }
      if (_disposed) return;

      // disableNetwork and enableNetwork are intentionally in separate
      // try/catch blocks: if disableNetwork throws or times out, we must
      // still attempt enableNetwork — otherwise a failure here could leave
      // the SDK's network genuinely disabled with nothing left to turn it
      // back on, which would be worse than doing nothing at all.
      try {
        await _firestore.disableNetwork().timeout(_kHeartbeatCallTimeout);
      } catch (_) {}
      if (_disposed) return;
      try {
        await _firestore.enableNetwork().timeout(_kHeartbeatCallTimeout);
      } catch (_) {}
      if (_disposed) return;

      final kitchenOnData = _kitchenOnData;
      if (kitchenOnData != null) {
        _kitchenRetryTimer?.cancel();
        _kitchenBackoffIndex = 0;
        _subscribeKitchen(
          kitchenOnData,
          _kitchenOnStreamError!,
          _kitchenOnParseError!,
        );
      }

      final controlsOnData = _controlsOnData;
      if (controlsOnData != null) {
        _controlsRetryTimer?.cancel();
        _controlsBackoffIndex = 0;
        _subscribeControls(
          controlsOnData,
          _controlsOnStreamError!,
          _controlsOnParseError!,
        );
      }
    } finally {
      _heartbeatRunning = false;
    }
  }

  void dispose() {
    _disposed = true;
    _kitchenSub?.cancel();
    _controlsSub?.cancel();
    _kitchenRetryTimer?.cancel();
    _controlsRetryTimer?.cancel();
    _heartbeatTimer?.cancel();
  }
}
