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
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log

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
            "LinkUp incoming calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Incoming LinkUp calls"
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
            // Bundle 223 (I): through the one permission queue.
            activity.askPermissions("call_notifications", arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION_PERMISSION)
        }
    }

    fun showIncoming(context: Context, callId: String, callerId: String, callerName: String) {
        if (callId.isBlank() || callerId.isBlank()) return
        initialize(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Bundle 179 (3.1): say WHY nothing shows (the phone keeps ringing).
        val fullScreen = fullScreenAllowed(manager)
        val state = alertState(context, manager, fullScreen)
        if (CallAlertPolicy.blocked(state)) {
            Log.w("LocalLinkCall", "CALL_NOTIFY_BLOCKED call=$callId reason=$state")
            return
        }
        val mode = CallAlertPolicy.mode(fullScreen)
        Log.i("LocalLinkCall", "CALL_NOTIFY_MODE call=$callId mode=$mode")

        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_ACTION, "open")
            putExtra(EXTRA_CALL_ID, callId)
            putExtra(EXTRA_CALLER_ID, callerId)
        }
        // Bundle 146: Accept OPENS the app (activity PendingIntent). As a
        // broadcast it accepted the call but never brought LocalLink to the
        // front, and Android 12+ blocks starting an activity from a
        // notification-action receiver ("trampoline"). Reject stays a
        // broadcast: it needs no screen.
        val acceptIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_ACCEPT
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_ACTION, "accept")
            putExtra(EXTRA_CALL_ID, callId)
            putExtra(EXTRA_CALLER_ID, callerId)
        }
        val rejectIntent = actionIntent(context, ACTION_REJECT, callId, callerId)

        val openPending = PendingIntent.getActivity(
            context,
            requestCode(callId, 0),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val acceptPending = PendingIntent.getActivity(
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
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFF209DEB.toInt()) // Bundle 141
            .setContentTitle("Incoming call")
            .setContentText(callerName.ifBlank { callerId })
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setContentIntent(openPending)
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

        // Bundle 179 (3.0b): full screen only when Android allows it.
        if (mode == CallAlertPolicy.MODE_FULL_SCREEN) builder.setFullScreenIntent(openPending, true)

        try {
            manager.notify(NOTIFICATION_ID, builder.build())
        } catch (e: Throwable) {
            // Bundle 179 (3.0): this used to vanish silently.
            Log.w("LocalLinkCall", "CALL_NOTIFY_FAILED call=$callId error=${e.javaClass.simpleName}:${e.message?.take(120)}")
            return
        }
        // Bundle 179 (3.2): does Android really show it? (Realme check)
        if (Build.VERSION.SDK_INT >= 23) {
            val app = context.applicationContext
            Handler(Looper.getMainLooper()).postDelayed({
                val shown = try {
                    (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                        .activeNotifications.any { it.id == NOTIFICATION_ID }
                } catch (_: Throwable) { null }
                Log.i("LocalLinkCall", "CALL_NOTIFY_POSTED call=$callId shown=${when (shown) { true -> "yes"; false -> "no"; null -> "unknown" }} mode=$mode")
            }, 700L)
        }
    }

    private fun fullScreenAllowed(manager: NotificationManager): Boolean? =
        if (Build.VERSION.SDK_INT >= 34) {
            try { manager.canUseFullScreenIntent() } catch (_: Throwable) { null }
        } else null

    /** Bundle 179 (3.4, 3.5): ok / permission / app_off / category_off / lockscreen_off. */
    fun alertState(context: Context): String {
        initialize(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return alertState(context, manager, fullScreenAllowed(manager))
    }

    private fun alertState(context: Context, manager: NotificationManager, fullScreen: Boolean?): String {
        val permission = Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val appOn = try { manager.areNotificationsEnabled() } catch (_: Throwable) { true }
        val importance = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try { manager.getNotificationChannel(CHANNEL_ID)?.importance } catch (_: Throwable) { null }
        } else null
        return CallAlertPolicy.state(permission, appOn, importance, fullScreen)
    }

    /**
     * Bundle 179 (3.4, 3.5): open Android's own page for the problem:
     * full-screen calls (Android 14+), the call category, or the app's
     * notification page.
     */
    fun openAlertSettings(context: Context, state: String) {
        val pkg = context.packageName
        val intents = mutableListOf<Intent>()
        if (state == CallAlertPolicy.LOCKSCREEN_OFF && Build.VERSION.SDK_INT >= 34) {
            intents += Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$pkg"))
        }
        if (state == CallAlertPolicy.CATEGORY_OFF && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intents += Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                .putExtra(Settings.EXTRA_CHANNEL_ID, CHANNEL_ID)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intents += Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
        }
        intents += Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
        for (intent in intents) {
            try {
                if (context !is android.app.Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                Log.i("LocalLinkCall", "CALL_ALERT_SETTINGS_OPENED state=$state page=${intent.action}")
                return
            } catch (_: Throwable) {}
        }
    }

    fun cancelIncoming(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID)
        // Bundle 146: lock-screen visibility is no longer dropped here. Dart
        // drives it for the whole live call (setCallLockScreen); clearing it on
        // accept pushed the call screen back behind the lock screen.
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
