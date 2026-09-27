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

        val dispatchIntent = Intent(context, MainActivity::class.java).apply {
            this.action = intent.action
            putExtra(CallNotificationManager.EXTRA_ACTION, action)
            putExtra(CallNotificationManager.EXTRA_CALL_ID, callId)
            putExtra(CallNotificationManager.EXTRA_CALLER_ID, callerId)
        }
        if (MainActivity.dispatchNotificationAction(dispatchIntent)) return
        dispatchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        context.startActivity(dispatchIntent)
    }
}
