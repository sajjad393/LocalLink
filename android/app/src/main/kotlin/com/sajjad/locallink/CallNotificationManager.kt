package com.sajjad.locallink

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build

/** Android-only incoming-call notification presentation. */
object CallNotificationManager {
    const val ACTION_OPEN = "com.sajjad.locallink.ACTION_OPEN_INCOMING_CALL"
    const val ACTION_ACCEPT = "com.sajjad.locallink.ACTION_ACCEPT_INCOMING_CALL"
    const val ACTION_REJECT = "com.sajjad.locallink.ACTION_REJECT_INCOMING_CALL"
    const val EXTRA_ACTION = "call_notification_action"
    const val EXTRA_CALL_ID = "call_id"
    const val EXTRA_CALLER_ID = "caller_id"
    private const val CHANNEL_ID = "locallink_incoming_calls"
    private const val NOTIFICATION_ID = 4101
    private const val REQUEST_NOTIFICATION_PERMISSION = 7743

    fun initialize(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "LocalLink incoming calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Incoming LocalLink calls"
            setSound(null, null)
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    fun requestNotificationPermission(activity: MainActivity) {
        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION_PERMISSION)
        }
    }

    fun showIncoming(context: Context, callId: String, callerId: String, callerName: String) {
        if (callId.isBlank() || callerId.isBlank()) return
        initialize(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return

        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_ACTION, "open")
            putExtra(EXTRA_CALL_ID, callId)
            putExtra(EXTRA_CALLER_ID, callerId)
        }
        val acceptIntent = actionIntent(context, ACTION_ACCEPT, callId, callerId)
        val rejectIntent = actionIntent(context, ACTION_REJECT, callId, callerId)

        val openPending = PendingIntent.getActivity(
            context,
            requestCode(callId, 0),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val acceptPending = PendingIntent.getBroadcast(
            context,
            requestCode(callId, 1),
            acceptIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val rejectPending = PendingIntent.getBroadcast(
            context,
            requestCode(callId, 2),
            rejectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle("Incoming call")
            .setContentText(callerName.ifBlank { callerId })
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setContentIntent(openPending)
            .setFullScreenIntent(openPending, true)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(context, android.R.drawable.sym_action_call),
                    "Accept",
                    acceptPending,
                ).build(),
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(context, android.R.drawable.ic_menu_close_clear_cancel),
                    "Reject",
                    rejectPending,
                ).build(),
            )

        manager.notify(NOTIFICATION_ID, builder.build())
    }

    fun cancelIncoming(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID)
        if (Build.VERSION.SDK_INT >= 27 && context is MainActivity) {
            context.clearCallLockScreen()
        }
    }

    fun cancelAll(context: Context) {
        cancelIncoming(context)
    }

    private fun actionIntent(context: Context, action: String, callId: String, callerId: String) =
        Intent(context, CallNotificationActionReceiver::class.java).apply {
            this.action = action
            putExtra(EXTRA_ACTION, action.removePrefix("com.sajjad.locallink.ACTION_").lowercase())
            putExtra(EXTRA_CALL_ID, callId)
            putExtra(EXTRA_CALLER_ID, callerId)
        }

    private fun requestCode(callId: String, action: Int): Int =
        10000 + (callId.hashCode() and 0x7fff) * 3 + action
}
