package com.whynotcafe.kitchen_display

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes a "restart" method over `kitchen_display/restart` that kills and
 * relaunches the whole process, not just the Flutter engine/isolate. A
 * Dart-level-only restart would leave native singletons (notably the
 * Firestore SDK's gRPC connection — the thing suspected of getting wedged in
 * the field) alive and unchanged, defeating the point of the restart. This
 * mirrors [BootReceiver]'s relaunch-the-activity approach, just triggered
 * from Dart instead of from a boot event.
 */
class MainActivity : FlutterActivity() {
    private val restartChannel = "kitchen_display/restart"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, restartChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "restart") {
                    result.success(null)
                    restartProcess()
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun restartProcess() {
        // Targets MainActivity directly, the same way BootReceiver does,
        // rather than packageManager.getLaunchIntentForPackage(packageName)
        // — that can return null on some OEM Android TV launchers, which
        // would kill the process with nothing left to relaunch it, turning
        // this "safety net" into a permanently blank screen.
        try {
            val launchIntent = Intent(applicationContext, MainActivity::class.java)
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            startActivity(launchIntent)
        } catch (e: Exception) {
            // If even the relaunch itself throws (e.g. a background-activity-
            // launch restriction), still fall through to exit(0) below — a
            // killed process is recoverable (by the user, or a future watchdog),
            // a process that fails to exit here is not.
        }
        Runtime.getRuntime().exit(0)
    }
}
