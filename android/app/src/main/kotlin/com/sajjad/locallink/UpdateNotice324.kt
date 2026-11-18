package com.sajjad.locallink

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Bundle 324 (324-A, shape B): ONE silent notification for the update itself.
 *
 * Silent on purpose: it never buzzes, never makes a sound, and changes only
 * when the percentage does (setOnlyAlertOnce). It is the card on the screen
 * (`update_banner_324.dart`) in the shade, for the owner who left the app.
 *
 * steps: `getting` (with %), `ready` (no %), `installing`, `failed`.
 */
object UpdateNotice324 {
    private const val CHANNEL_ID = "linkup_update_324"
    private const val TAG = "linkup_update_324"
    private const val ID = 3241

    fun show(context: Context, args: Map<String, Any?>) {
        if (!LocalLinkNotificationManager.notificationsEnabled(context)) return
        initialize(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val step = (args["step"] as? String).orEmpty()
        val pct = (args["progress"] as? Number)?.toInt()?.coerceIn(0, 100) ?: 0
        val title = (args["title"] as? String)?.trim().orEmpty().ifEmpty { "LinkUp" }
        val line = (args["line"] as? String)?.trim().orEmpty()
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Ready / installing / failed have no bar: a finished bar said 100% twice.
        val bar = step == "getting" && pct > 0
        val b = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ChatRequestNotifier307.BLUE)
            .setContentTitle(title)
            .setContentText(line)
            .setStyle(NotificationCompat.BigTextStyle().bigText(line))
            .setOngoing(step == "getting" || step == "installing")
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentIntent(open)
            .setAutoCancel(step == "ready" || step == "failed")
        if (bar) b.setProgress(100, pct, false)
        try {
            manager.notify(TAG, ID, b.build())
        } catch (_: SecurityException) {
        }
    }

    fun cancel(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        manager.cancel(TAG, ID)
    }

    private fun initialize(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            Words304.w(context, "LinkUp update"),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = Words304.w(context, "The update coming to this phone (silent)")
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }
}
