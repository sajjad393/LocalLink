package com.sajjad.locallink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Notification actions are converted into internal MainActivity intents.
 * CallSessionManager performs the authoritative call-session/caller validation in Dart.
 */
class CallNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = when (intent.action) {
            CallNotificationManager.ACTION_ACCEPT -> "accept"
            CallNotificationManager.ACTION_REJECT -> "reject"
            else -> return
        }
        val callId = intent.getStringExtra(CallNotificationManager.EXTRA_CALL_ID)?.trim().orEmpty()
        val callerId = intent.getStringExtra(CallNotificationManager.EXTRA_CALLER_ID)?.trim().orEmpty()
        if (callId.isEmpty() || callerId.isEmpty()) return
        // Bundle 146: Accept now opens MainActivity directly; only Reject (and
        // an Accept on a notification posted by an older build) lands here.
        android.util.Log.i("LocalLinkCall", "CALL_NOTIFICATION_ACTION action=$action source=receiver call=$callId")

        val dispatchIntent = Intent(context, MainActivity::class.java).apply {
            this.action = intent.action
            putExtra(CallNotificationManager.EXTRA_ACTION, action)
            putExtra(CallNotificationManager.EXTRA_CALL_ID, callId)
            putExtra(CallNotificationManager.EXTRA_CALLER_ID, callerId)
        }
        if (MainActivity.dispatchNotificationAction(dispatchIntent)) return
        // Bundle 162 (4.2): the app screen is closed. Android 12+ blocks
        // opening it from here, so Reject is done right here: stop ringing,
        // remove the call notification, tell the caller (voice signalling
        // only; video untouched).
        if (action == "reject") {
            CallRingtoneManager.stop()
            CallNotificationManager.cancelIncoming(context)
            val pending = goAsync()
            Thread({
                val sent = try {
                    LocalLinkTransportService.send(callerId, mapOf(
                        "type" to "call_reject",
                        "call_id" to callId,
                        "recipient_id" to callerId,
                        "reason" to "rejected",
                        "direct" to true,
                        "mesh_call" to true,
                        "transport_mode" to "offline_mesh",
                    ))
                } catch (_: Exception) { false }
                android.util.Log.i("LocalLinkCall", "CALL_REJECT_NATIVE call=$callId sent=$sent")
                pending.finish()
            }, "locallink-call-reject").start()
            return
        }
        dispatchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        context.startActivity(dispatchIntent)
    }
}
