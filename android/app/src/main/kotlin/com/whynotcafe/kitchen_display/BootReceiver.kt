package com.whynotcafe.kitchen_display

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Relaunches MainActivity after the device finishes booting, so the display
 * recovers on its own after a power cut with no one around to restart it by
 * hand. Some Android versions/OEM TV skins restrict starting an Activity
 * from the background even here — if that turns out to be the case on the
 * real device, fall back to Fully Kiosk's "App Mode" or Screen Pinning and
 * relaunch by hand until that's set up.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val launchIntent = Intent(context, MainActivity::class.java)
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(launchIntent)
        }
    }
}
