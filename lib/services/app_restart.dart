import 'package:flutter/services.dart';

/// Kills and relaunches the native Android process via [MainActivity]'s
/// `kitchen_display/restart` method channel. Deliberately not a Flutter-only
/// "restart" plugin — this needs to reset native singletons (the Firestore
/// SDK's gRPC connection) that a widget-tree-only restart would leave
/// untouched.
class AppRestart {
  static const MethodChannel _channel = MethodChannel('kitchen_display/restart');

  static Future<void> restart() async {
    try {
      await _channel.invokeMethod('restart');
    } catch (_) {
      // Best-effort — if the channel call itself fails, there's nothing
      // more this process can do to un-wedge itself.
    }
  }
}
