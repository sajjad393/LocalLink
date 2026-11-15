package com.sajjad.locallink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat

/**
 * Bundle 307 (TODO_307 C1): the phone card of a Get chat request - one
 * notification per request, grouped, like a ride card.
 *
 * - Android 16+ (API 36): framework ProgressStyle (points at 33 / 66 / 100)
 *   and "request promoted ongoing", so it becomes a Live Update while the
 *   request runs. Sent / Reached / Answer coming = ongoing; Ready and
 *   No messages are normal notifications (Android: only ongoing cards are
 *   promoted; the group summary never is).
 * - Android 7-15: NotificationCompat with the same words and a plain bar.
 *
 * Bundle 314 (3, pick B): on Android 16+ the track has a bubble at the start,
 * a check at the end and a ring tracker that rocks +-4 every 3 s while the
 * request is Sent / Reached ("same like the inner card"). Android has no
 * animation in notifications, so a main-looper timer posts the card again
 * with the next position. It stops after 10 min (`rock_until` from Dart), on
 * the next step (parts / Ready / cancel) and when the card is removed.
 * Android 15 and older keep the sliding line while waiting and a filled bar
 * once parts come (USER PICK).
 *
 * Dart sends the final words (English or Urdu); this file only draws them.
 * Updates are silent (no sound channel). Ready is posted ONCE on the "Chat
 * ready" channel = the message tone + one short buzz; later posts of a Ready
 * card go back to the silent channel.
 */
object ChatRequestNotifier307 {
    const val CHANNEL_ID = "locallink_chat_requests_v1"
    const val READY_CHANNEL_ID = "locallink_chat_ready_v1"
    const val GROUP_KEY = "linkup_chat_requests"
    const val TAG = "linkup_chat_request_307"
    const val SUMMARY_TAG = "linkup_chat_request_307_summary"
    const val SUMMARY_ID = 307
    /** Tap / "Open chat": MainActivity gets ACTION_OPEN with this action. */
    const val TAP_ACTION = "open_chat_request"
    const val EXTRA_REQUEST_ID = "chat_request_id"
    /** Notification.EXTRA_REQUEST_PROMOTED_ONGOING (API 36.1); a plain key, so older SDK stubs compile. */
    const val EXTRA_PROMOTED = "android.requestPromotedOngoing"
    const val EMPTY_TIMEOUT_MS = 10_000L
    const val BLUE = 0xFF209DEB.toInt()
    const val GREEN = 0xFF22C55E.toInt()
    const val GREY = 0xFF8E8E93.toInt()
    /** Bundle 314: the card's "waiting" orange (Sent / Reached). */
    const val ORANGE = 0xFFF59E0B.toInt()

    /** The stops on the track (Reached, Answer, Ready). */
    val POINTS = listOf(33, 66, 100)

    /** What one card looks like (pure, unit-tested). */
    data class Plan(
        val step: String,
        val progress: Int,
        val indeterminate: Boolean,
        val ongoing: Boolean,
        val promoted: Boolean,
        val timeoutMs: Long,
        val openButton: Boolean,
        val grey: Boolean,
        val readyPointGreen: Boolean,
        val channel: String,
        val alert: Boolean,
        /** Bundle 314: the tracker rocks (Android 16+, Sent / Reached). */
        val rock: Boolean = false,
        /** Bundle 314: Android 15 and older draw the sliding line. */
        val compatSliding: Boolean = false,
    )

    /** Bundle 314 (3): how far the tracker rocks and how often. */
    const val ROCK_STEP = 4
    const val ROCK_EVERY_MS = 3_000L

    fun plan(step: String, progress: Int, buzz: Boolean): Plan {
        val p = progress.coerceIn(0, 100)
        return when (step) {
            "ready" -> Plan("ready", 100, false, ongoing = false, promoted = false, timeoutMs = 0,
                openButton = true, grey = false, readyPointGreen = true,
                channel = if (buzz) READY_CHANNEL_ID else CHANNEL_ID, alert = buzz)
            "empty", "cancelled" -> Plan(step, p, false, ongoing = false, promoted = false, timeoutMs = EMPTY_TIMEOUT_MS,
                openButton = false, grey = true, readyPointGreen = false, channel = CHANNEL_ID, alert = false)
            "reached", "coming" -> Plan(step, p, false, ongoing = true, promoted = true, timeoutMs = 0,
                openButton = false, grey = false, readyPointGreen = false, channel = CHANNEL_ID, alert = false,
                rock = step == "reached", compatSliding = step == "reached")
            else -> Plan("sent", p, true, ongoing = true, promoted = true, timeoutMs = 0,
                openButton = false, grey = false, readyPointGreen = false, channel = CHANNEL_ID, alert = false,
                rock = true, compatSliding = true)
        }
    }

    /** API 36+ draws the Live Update (ProgressStyle); below = the plain bar. */
    fun useProgressStyle(sdk: Int): Boolean = sdk >= 36

    /** Bundle 314 (3): the tracker position on rock tick [tick] (0 = the
     *  step's own place, then +4 / -4 / +4 ...), never outside 0-100. */
    fun rockProgress(base: Int, tick: Int): Int {
        val b = base.coerceIn(0, 100)
        if (tick <= 0) return b
        val at = if (tick % 2 == 1) b + ROCK_STEP else b - ROCK_STEP
        return at.coerceIn(0, 100)
    }

    /** Bundle 314 (3): rock now? Android 16+, Sent / Reached, before [rockUntilMs]. */
    /** Bundle 314 (3): the tracker ring in the step colour, like the card
     *  (orange Sent / Reached, blue Coming, green Ready, grey ended). */
    fun trackerColor(plan: Plan): Int = when {
        plan.grey -> GREY
        plan.step == "ready" -> GREEN
        plan.step == "coming" -> BLUE
        else -> ORANGE
    }

    fun shouldRock(sdk: Int, plan: Plan, rockUntilMs: Long, nowMs: Long): Boolean =
        useProgressStyle(sdk) && plan.rock && rockUntilMs > nowMs

    private val main by lazy { Handler(Looper.getMainLooper()) }
    private val rockers = HashMap<String, Runnable>()

    private fun stopRock(requestId: String) {
        rockers.remove(requestId)?.let { main.removeCallbacks(it) }
    }

    private fun stopAllRocks() {
        for (r in rockers.values) main.removeCallbacks(r)
        rockers.clear()
    }

    /** Posts the same card again every 3 s with the next tracker place. */
    private fun startRock(context: Context, id: String, args: Map<String, Any?>, rockUntilMs: Long) {
        val app = context.applicationContext
        var tick = 0
        val r = object : Runnable {
            override fun run() {
                if (rockers[id] !== this) return
                if (System.currentTimeMillis() >= rockUntilMs) {
                    rockers.remove(id)
                    post(app, args, 0) // back to the step's own place
                    return
                }
                tick++
                if (!post(app, args, tick)) {
                    rockers.remove(id)
                    return
                }
                main.postAtTime(this, SystemClock.uptimeMillis() + ROCK_EVERY_MS)
            }
        }
        rockers[id] = r
        main.postDelayed(r, ROCK_EVERY_MS)
    }

    /** Stable, never 0 (the tag keeps it apart from message ids). */
    fun notificationId(requestId: String): Int {
        var h = 17
        for (c in requestId.trim()) h = (h * 31 + c.code) and 0x3FFFFFFF
        return if (h == 0) 1 else h
    }

    fun requestCode(requestId: String, button: Int): Int =
        30700 + (notificationId(requestId) and 0x3fff) * 2 + button

    /** The channel names come from Dart (English or Urdu); creating again only renames. */
    fun initialize(context: Context, name: String, readyName: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL_ID,
            name.ifBlank { "LinkUp chat requests" },
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        })
        if (manager.getNotificationChannel(READY_CHANNEL_ID) == null || readyName.isNotBlank()) {
            manager.createNotificationChannel(NotificationChannel(
                READY_CHANNEL_ID,
                readyName.ifBlank { "Chat ready" },
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 140)
                val soundId = context.resources.getIdentifier("locallink_message", "raw", context.packageName)
                if (soundId != 0) {
                    setSound(
                        Uri.parse("android.resource://${context.packageName}/$soundId"),
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                }
            })
        }
    }

    /** One card. [args] = the method-channel arguments from Dart. */
    fun show(context: Context, args: Map<String, Any?>) {
        val id = (args["request_id"] as? String)?.trim().orEmpty()
        if (id.isEmpty()) return
        stopRock(id) // Bundle 314: a new step / number = a new card
        if (!post(context, args, 0)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        showSummary(context, manager, args)
        val step = plan((args["step"] as? String).orEmpty(), (args["progress"] as? Number)?.toInt() ?: 0, false)
        val until = (args["rock_until"] as? Number)?.toLong() ?: 0L
        if (shouldRock(Build.VERSION.SDK_INT, step, until, System.currentTimeMillis())) {
            // Only the first post may sound (Ready); the rock posts never do.
            startRock(context, id, args + ("buzz" to false), until)
        }
    }

    /** Draws one card; [tick] > 0 = a rock post. False = not posted. */
    private fun post(context: Context, args: Map<String, Any?>, tick: Int): Boolean {
        val id = (args["request_id"] as? String)?.trim().orEmpty()
        if (id.isEmpty()) return false
        if (!LocalLinkNotificationManager.notificationsEnabled(context)) return false
        if (tick == 0) {
            initialize(context, (args["channel_name"] as? String).orEmpty(), (args["ready_channel_name"] as? String).orEmpty())
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return false
        val plan = plan((args["step"] as? String).orEmpty(), (args["progress"] as? Number)?.toInt() ?: 0, args["buzz"] == true)
        val title = (args["title"] as? String)?.trim().orEmpty()
        val text = (args["text"] as? String)?.trim().orEmpty()
        val names = (args["sub_text"] as? String)?.trim().orEmpty()
        val short = (args["short"] as? String)?.trim().orEmpty()
        val openLabel = (args["open_label"] as? String)?.trim().orEmpty()
        val faces = (args["names"] as? List<*>)?.mapNotNull { (it as? String)?.trim()?.takeIf { s -> s.isNotEmpty() } }.orEmpty()
        val whenMs = (args["when"] as? Number)?.toLong()?.takeIf { it > 0 } ?: System.currentTimeMillis()
        val open = PendingIntent.getActivity(
            context,
            requestCode(id, 0),
            tapIntent(context, id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val icon = facesIcon(faces)
        // Same rule as useProgressStyle(); written out so Android lint sees the API check.
        val notification = if (Build.VERSION.SDK_INT >= 36) {
            buildLive(context, plan, title, text, names, short, openLabel, icon, whenMs, open, rockProgress(plan.progress, tick))
        } else {
            buildCompat(context, plan, title, text, names, openLabel, icon, whenMs, open)
        }
        try {
            manager.notify(TAG, notificationId(id), notification)
        } catch (_: SecurityException) {
            return false
        }
        return true
    }

    fun cancel(context: Context, requestId: String, args: Map<String, Any?> = emptyMap()) {
        stopRock(requestId.trim())
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (requestId.isNotBlank()) manager.cancel(TAG, notificationId(requestId))
        showSummary(context, manager, args)
    }

    fun cancelAll(context: Context) {
        stopAllRocks()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        try {
            for (n in manager.activeNotifications) {
                if (n.tag == TAG || n.tag == SUMMARY_TAG) manager.cancel(n.tag, n.id)
            }
        } catch (_: Exception) {}
        manager.cancel(SUMMARY_TAG, SUMMARY_ID)
    }

    /** "3 chat requests · 1 ready" + one line per request (2+ cards only). */
    private fun showSummary(context: Context, manager: NotificationManager, args: Map<String, Any?>) {
        val count = (args["summary_count"] as? Number)?.toInt() ?: return
        if (count < 2) {
            manager.cancel(SUMMARY_TAG, SUMMARY_ID)
            return
        }
        val title = (args["summary_title"] as? String)?.trim().orEmpty()
        val lines = (args["summary_lines"] as? List<*>)?.mapNotNull { it as? String }.orEmpty()
        val style = NotificationCompat.InboxStyle().setBigContentTitle(title)
        for (l in lines.take(6)) style.addLine(l)
        val n = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(BLUE)
            .setContentTitle(title)
            .setContentText(lines.firstOrNull().orEmpty())
            .setStyle(style)
            .setGroup(GROUP_KEY)
            .setGroupSummary(true)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .build()
        try {
            manager.notify(SUMMARY_TAG, SUMMARY_ID, n)
        } catch (_: SecurityException) {}
    }

    private fun tapIntent(context: Context, requestId: String): Intent =
        Intent(context, MainActivity::class.java).apply {
            action = LocalLinkNotificationManager.ACTION_OPEN
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) identifier = "linkup-chat-request-$requestId"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(LocalLinkNotificationManager.EXTRA_ACTION, TAP_ACTION)
            putExtra(EXTRA_REQUEST_ID, requestId)
        }

    @RequiresApi(36)
    private fun buildLive(
        context: Context,
        plan: Plan,
        title: String,
        text: String,
        names: String,
        short: String,
        openLabel: String,
        icon: Bitmap?,
        whenMs: Long,
        open: PendingIntent,
        at: Int,
    ): Notification {
        // Bundle 314 (3, pick B): bubble -> ring tracker -> check; the ring
        // stands on its step (Sent 4, Reached 33) and rocks from there.
        val style = Notification.ProgressStyle()
            .setStyledByProgress(true) // filled up to the tracker
            .setProgressSegments(listOf(Notification.ProgressStyle.Segment(100).setColor(if (plan.grey) GREY else BLUE)))
            .setProgressPoints(POINTS.map { at ->
                Notification.ProgressStyle.Point(at).setColor(
                    if (at == 100 && plan.readyPointGreen) GREEN else if (plan.grey) GREY else BLUE,
                )
            })
            .setProgressTrackerIcon(Icon.createWithResource(context, R.drawable.ic_req314_tracker).setTint(trackerColor(plan)))
            .setProgressStartIcon(Icon.createWithResource(context, R.drawable.ic_req314_start))
            .setProgressEndIcon(Icon.createWithResource(context, R.drawable.ic_req314_end))
            .setProgress(at)
            .setProgressIndeterminate(false)
        val b = Notification.Builder(context, plan.channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(BLUE)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(style)
            .setOngoing(plan.ongoing)
            .setOnlyAlertOnce(!plan.alert)
            .setWhen(whenMs)
            .setShowWhen(true)
            .setGroup(GROUP_KEY)
            .setGroupAlertBehavior(Notification.GROUP_ALERT_CHILDREN)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(open)
            .setAutoCancel(plan.step == "ready")
            .setPublicVersion(
                Notification.Builder(context, plan.channel)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setColor(BLUE)
                    .setContentTitle(title)
                    .setStyle(Notification.ProgressStyle().setProgress(plan.progress).setProgressIndeterminate(false))
                    .build(),
            )
        if (names.isNotEmpty()) b.setSubText(names)
        if (icon != null) b.setLargeIcon(icon)
        if (short.isNotEmpty() && plan.ongoing) b.setShortCriticalText(short)
        if (plan.timeoutMs > 0) b.setTimeoutAfter(plan.timeoutMs)
        if (plan.openButton && openLabel.isNotEmpty()) {
            b.addAction(Notification.Action.Builder(
                Icon.createWithResource(context, android.R.drawable.sym_action_chat), openLabel, open,
            ).build())
        }
        if (plan.promoted) b.extras.putBoolean(EXTRA_PROMOTED, true)
        return b.build()
    }

    private fun buildCompat(
        context: Context,
        plan: Plan,
        title: String,
        text: String,
        names: String,
        openLabel: String,
        icon: Bitmap?,
        whenMs: Long,
        open: PendingIntent,
    ): Notification {
        val b = NotificationCompat.Builder(context, plan.channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(if (plan.grey) GREY else BLUE)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(plan.ongoing)
            .setOnlyAlertOnce(!plan.alert)
            .setWhen(whenMs)
            .setShowWhen(true)
            .setGroup(GROUP_KEY)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(open)
            .setAutoCancel(plan.step == "ready")
            .setPublicVersion(
                NotificationCompat.Builder(context, plan.channel)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setColor(BLUE)
                    .setContentTitle(title)
                    .build(),
            )
        // Bundle 314 (USER PICK): the sliding line while waiting (Sent /
        // Reached), a filled bar once parts come.
        if (plan.step != "ready" && !plan.grey) b.setProgress(100, plan.progress, plan.compatSliding)
        if (!plan.alert) b.setSilent(true)
        if (plan.alert && Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            // Below Android 8 there are no channels: the message tone only (no buzz permission).
            val soundId = context.resources.getIdentifier("locallink_message", "raw", context.packageName)
            if (soundId != 0) b.setSound(Uri.parse("android.resource://${context.packageName}/$soundId"))
        }
        if (names.isNotEmpty()) b.setSubText(names)
        if (icon != null) b.setLargeIcon(icon)
        if (plan.timeoutMs > 0) b.setTimeoutAfter(plan.timeoutMs)
        if (plan.openButton && openLabel.isNotEmpty()) b.addAction(0, openLabel, open)
        return b.build()
    }

    /** Same colours as the app's avatar circles (LocalLinkAvatarColor.forName). */
    private val palette = intArrayOf(
        0xFF1FD7D4.toInt(), 0xFF7C6BF0.toInt(), 0xFF2F6FF6.toInt(), 0xFFE74BC8.toInt(),
        0xFF2BA0F0.toInt(), 0xFF8E58F5.toInt(), 0xFF00A8B5.toInt(), 0xFFD95FA0.toInt(),
    )

    fun colorOf(name: String): Int {
        var hash = 0
        for (c in name.trim()) hash = (hash * 31 + c.code) and 0x7FFFFFFF
        return if (name.isBlank()) palette[0] else palette[hash % palette.size]
    }

    fun initialOf(name: String): String =
        name.trim().removePrefix("@").firstOrNull()?.uppercaseChar()?.toString() ?: "?"

    /** Two overlapping letter faces (one face for a group / one name). */
    private fun facesIcon(names: List<String>): Bitmap? {
        if (names.isEmpty()) return null
        return try {
            val size = 192
            val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(out)
            val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
            fun face(name: String, cx: Float, cy: Float, r: Float, ring: Boolean) {
                if (ring) {
                    paint.color = android.graphics.Color.WHITE
                    canvas.drawCircle(cx, cy, r + 6f, paint)
                }
                paint.color = colorOf(name)
                canvas.drawCircle(cx, cy, r, paint)
                paint.color = android.graphics.Color.WHITE
                paint.textAlign = android.graphics.Paint.Align.CENTER
                paint.typeface = android.graphics.Typeface.DEFAULT_BOLD
                paint.textSize = r * 0.95f
                canvas.drawText(initialOf(name), cx, cy - (paint.descent() + paint.ascent()) / 2f, paint)
            }
            if (names.size < 2) {
                face(names[0], size / 2f, size / 2f, size / 2f, false)
            } else {
                face(names[0], 62f, 62f, 58f, false)
                face(names[1], 126f, 126f, 58f, true)
            }
            out
        } catch (_: Exception) {
            null
        }
    }
}
