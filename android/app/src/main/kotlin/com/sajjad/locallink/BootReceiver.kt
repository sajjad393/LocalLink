package com.sajjad.locallink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Bundle 140: bring the transport service back after a device reboot.
 * Bundle 164 (4.3): when Android refuses the start (Android 12+ background
 * rules, brand battery savers) it is no longer silent: BOOT_START_FAILED is
 * logged and a quiet "LocalLink is ready - Tap to reconnect." notice is shown.
 * Opening the app removes it.
 * Bundle 169 (4.3): after a good start the app's own engine also starts in
 * the background ([BackgroundEngine]); the notice shows only if it can't.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val failure = try {
            LocalLinkTransportService.startFromBoot(context)
        } catch (e: Exception) {
            e.javaClass.simpleName
        }
        if (failure == null) {
            Log.i(TAG, "BOOT_START_OK")
            // Bundle 169 (4.3): start the app's own engine in the background so
            // messages and notifications work before the app is opened.
            val skip = try {
                BackgroundEngine.startAfterBoot(context, bootStartOk = true)
            } catch (e: Throwable) {
                Log.w(TAG, "BOOT_ENGINE_FAILED reason=${e.javaClass.simpleName}")
                "error"
            }
            if (BackgroundEnginePolicy.showReconnectNotice(skip)) {
                try {
                    LocalLinkNotificationManager.showBootReconnect(context)
                } catch (_: Exception) {}
            }
            return
        }
        Log.w(TAG, "BOOT_START_FAILED reason=$failure")
        try {
            LocalLinkNotificationManager.showBootReconnect(context)
        } catch (_: Exception) {}
    }

    companion object {
        const val TAG = "LocalLinkBoot"
    }
}
