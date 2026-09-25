import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../logic/grid_layout.dart';
import '../models/kitchen_order.dart';
import '../services/app_restart.dart';
import '../services/kitchen_firestore_service.dart';
// Google Drive-backed idle slideshow — disabled in favor of a static logo
// (see `_IdleView` below). Left in the tree, commented out, rather than
// deleted: see `lib/widgets/idle_media_slideshow.dart` for the full logic
// if this ever needs to come back.
// import '../widgets/idle_media_slideshow.dart';
import '../widgets/order_tile.dart';

/// If no snapshot (successful or not) has arrived on either listener for
/// this long, the display is considered stuck and a full restart is
/// triggered as a safety net beyond the heartbeat's own reconnect attempts.
const Duration _kStaleThreshold = Duration(minutes: 8);

/// Floor between auto-restarts, persisted across process restarts. Without
/// this, a genuine extended outage (e.g. the café's wifi AP down overnight)
/// would re-trigger the watchdog every [_kStaleThreshold] once it wakes back
/// up with no data yet — a restart every ~8 minutes for hours. A restart is
/// harmless on its own, so this exists purely to keep an outage from being
/// flappy/visible, not to avoid the restart itself.
const Duration _kRestartCooldown = Duration(minutes: 15);
const String _kDeviceIdPrefsKey = 'device_id';
const String _kLastAutoRestartPrefsKey = 'last_auto_restart_at_millis';

/// Bound on `shared_preferences` calls on the auto-restart path. Without
/// this, a wedged platform channel could make `SharedPreferences` itself
/// hang forever — and since that call has no timeout of its own, the one
/// safety-critical action in this whole file (the actual restart) would
/// never run, blocked on an await that never resolves.
const Duration _kPrefsCallTimeout = Duration(seconds: 5);

/// The one and only screen this app has: a read-only, non-interactive,
/// always-on kitchen display. Dead end by design — no buttons, no touch
/// targets, no navigation.
class KitchenDisplayScreen extends StatefulWidget {
  const KitchenDisplayScreen({super.key});

  @override
  State<KitchenDisplayScreen> createState() => _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends State<KitchenDisplayScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _service = KitchenFirestoreService();

  List<KitchenOrder> _orders = const [];
  bool _kitchenDisplayEnabled = true;
  Timer? _ticker;
  Timer? _longPressTimer;
  bool _disposed = false;
  bool _restartTriggered = false;
  bool _checkingAutoRestart = false;
  final FocusNode _focusNode = FocusNode();
  late String _deviceId;

  /// Drives the screen-edge pulse (see `_AlertBorder`) so it's visible from
  /// across a room, not just up close on the tile itself — smooth 60fps,
  /// independent of `_ticker`'s once-a-second rebuild.
  late final AnimationController _alert = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyImmersiveMode();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _enableWakelock();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      _checkStaleness();
    });

    _service.listenKitchenDisplay(
      onData: (orders, exists) {
        if (mounted) setState(() => _orders = orders);
      },
      onStreamError: (error) {},
      onParseError: (error) {},
    );

    _service.listenDisplayControls(
      onData: (enabled, exists) {
        if (mounted) setState(() => _kitchenDisplayEnabled = enabled);
      },
      onStreamError: (error) {},
      onParseError: (error) {},
    );

    // The heartbeat (network toggle + resubscribe + telemetry) starts
    // immediately with a synchronous, in-memory device id — it must not
    // depend on SharedPreferences succeeding, or a plugin/platform hiccup
    // on that one call would silently disable the entire recovery
    // mechanism, not just telemetry. Persisting a stable cross-restart id
    // is layered on top, best-effort, afterward.
    _deviceId = _generateRandomId();
    _service.startHeartbeat(deviceId: _deviceId);
    _loadPersistedDeviceId();
  }

  String _generateRandomId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _loadPersistedDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(_kPrefsCallTimeout);
      final existing = prefs.getString(_kDeviceIdPrefsKey);
      if (existing != null) {
        _deviceId = existing;
      } else {
        await prefs.setString(_kDeviceIdPrefsKey, _deviceId).timeout(_kPrefsCallTimeout);
      }
    } catch (_) {
      // Best-effort — the heartbeat is already running with the in-memory
      // id generated at startup; only cross-restart telemetry correlation
      // is lost, not the recovery mechanism itself.
      return;
    }
    if (_disposed) return;
    _service.startHeartbeat(deviceId: _deviceId);
  }

  /// Runs every second off `_ticker`. Cheap in the common case (a null or
  /// fresh `lastSnapshotAt` returns immediately) — the `SharedPreferences`
  /// round trip only happens once staleness is already suspected, and
  /// `_checkingAutoRestart` prevents those async checks from overlapping if
  /// several ticks fire while one is still in flight.
  void _checkStaleness() {
    if (_disposed || _restartTriggered || _checkingAutoRestart) return;
    final last = _service.lastSnapshotAt;
    if (last == null) return;
    if (DateTime.now().difference(last) <= _kStaleThreshold) return;
    _checkingAutoRestart = true;
    _maybeAutoRestart().whenComplete(() => _checkingAutoRestart = false);
  }

  Future<void> _maybeAutoRestart() async {
    if (_disposed || _restartTriggered) return;
    SharedPreferences? prefs;
    DateTime? lastRestartAt;
    try {
      prefs = await SharedPreferences.getInstance().timeout(_kPrefsCallTimeout);
      final millis = prefs.getInt(_kLastAutoRestartPrefsKey);
      if (millis != null) {
        lastRestartAt = DateTime.fromMillisecondsSinceEpoch(millis);
      }
    } catch (_) {
      // Cooldown state unavailable (including a timed-out/wedged platform
      // channel) — fail open and allow the restart below. A missed cooldown
      // check is far safer than a plugin hiccup silently disabling the
      // watchdog's safety net forever.
    }
    if (_disposed || _restartTriggered) return;
    if (lastRestartAt != null &&
        DateTime.now().difference(lastRestartAt) < _kRestartCooldown) {
      return;
    }
    _restartTriggered = true;
    try {
      await prefs
          ?.setInt(_kLastAutoRestartPrefsKey, DateTime.now().millisecondsSinceEpoch)
          .timeout(_kPrefsCallTimeout);
    } catch (_) {
      // Same reasoning: never let a wedged/slow write to shared_preferences
      // delay the actual restart below.
    }
    await AppRestart.restart();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.select && key != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      // Nulled out inside the callback (not just on KeyUp) so a missed KeyUp
      // — e.g. a transient focus loss mid-press — can't leave a stale
      // non-null reference that silently blocks every future long-press via
      // the `??=` below.
      _longPressTimer ??= Timer(const Duration(seconds: 3), () {
        _longPressTimer = null;
        AppRestart.restart();
      });
    } else if (event is KeyUpEvent) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
    }
    return KeyEventResult.handled;
  }

  Future<void> _applyImmersiveMode() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
  }

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyImmersiveMode();
    }
  }

  @override
  void didChangeMetrics() {
    _applyImmersiveMode();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _longPressTimer?.cancel();
    _alert.dispose();
    _focusNode.dispose();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anyLongWait = _orders.any((o) => isLongWait(o.readySince, DateTime.now()));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Stack(
          children: [
            Positioned.fill(child: _buildContent()),
            if (anyLongWait) Positioned.fill(child: _AlertBorder(animation: _alert)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (!_kitchenDisplayEnabled) return const _PausedView();
    if (_orders.isEmpty) return const _IdleView();
    return _GridView(orders: _orders, now: DateTime.now());
  }
}

/// Pulsing red frame around the whole screen, shown whenever at least one
/// order is overdue (`isLongWait`) — big and far enough from the tiles
/// themselves to catch a customer's eye from across the counter, not just
/// someone standing right in front of the TV.
class _AlertBorder extends StatelessWidget {
  const _AlertBorder({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.35 + t * 0.65),
                width: 8 + t * 14,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PausedView extends StatelessWidget {
  const _PausedView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.pause_circle_outline,
            color: Colors.white.withValues(alpha: 0.38),
            size: 120,
          ),
          const SizedBox(height: 24),
          Text(
            'Display temporarily unavailable',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 32,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while no orders are ready. Used to rotate through a Google
/// Drive-hosted photo/video slideshow (see `lib/widgets/idle_media_slideshow.dart`,
/// disabled — commented out — in `kitchen_display_screen.dart`'s imports);
/// replaced with a plain static logo.
class _IdleView extends StatelessWidget {
  const _IdleView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        'assets/images/logo.png',
        width: 420,
      ),
    );
  }
}

class _GridView extends StatelessWidget {
  const _GridView({required this.orders, required this.now});

  final List<KitchenOrder> orders;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final split = splitOrdersForGrid(orders);
    final columns = gridColumnsForCount(split.mainTiles.length);
    final rows = gridRowsForCount(split.mainTiles.length, columns);

    return Column(
      children: [
        Expanded(
          child: Column(
            children: List.generate(rows, (r) {
              return Expanded(
                child: Row(
                  children: List.generate(columns, (c) {
                    final index = r * columns + c;
                    if (index >= split.mainTiles.length) {
                      return const Expanded(child: SizedBox.shrink());
                    }
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: OrderTile(order: split.mainTiles[index], now: now),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
        if (split.overflow.isNotEmpty) _OverflowBar(orders: split.overflow),
      ],
    );
  }
}

class _OverflowBar extends StatelessWidget {
  const _OverflowBar({required this.orders});

  final List<KitchenOrder> orders;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            'ALSO READY:',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: orders
                  .map(
                    (o) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        child: Text(
                          '#${o.orderNumber}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
