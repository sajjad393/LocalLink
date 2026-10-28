package com.sajjad.locallink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Bundle 140: bring the transport service back after a device reboot.
 * Best-effort — the service's own startCommand already guards the
 * Android 12+ foreground-service background restrictions; if the OS refuses,
 * the existing START_STICKY/next-open path resumes it.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        try {
            LocalLinkTransportService.start(context)
        } catch (_: Exception) {
            // OS-level FGS restriction: ignored on purpose; app resumes next open.
        }
    }
}
