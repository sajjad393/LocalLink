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
 * Bundle 317 (G7): after "Chat ready" the same card goes on while the
 * chat's files come: `files` (blue), `files_wait` (orange, no new parts for
 * 2 min; swipeable after 30 min) and `files_done` (green, silent). Android
 * 16+: one ProgressStyle segment per 8 MB trip (max 7) and a photo tracker;
 * Android 15 and older: a bar by MB. Buttons Open chat + Stop files. The
 * only buzz stays "Chat ready".
 *
 * Bundle 321 (N1-N3, USER PICK B "minimal", same look on every phone): the
 * card is ONE line (the chat + "3/7" / "waiting" / a green check), no text
 * line and no buttons (tap opens the chat; Stop is inside the chat). The bar
 * has one piece per file (green points when files are in), the tracker is
 * the kind of file coming (photo / video / mic; hourglass while waiting),
 * start = the sender's letter, end = the check; the large picture is the
 * file coming (the faces when there is none). Android 16+ draws it with
 * ProgressStyle; Android 15 and older get the same card from [ChatCard321]
 * (a custom body + a picture of the same bar). Ready / all files here = no
 * bar, only the line with the check.
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
    /** Bundle 318 (K7): "Up to date" goes by itself after this. */
    const val UP_TO_DATE_TIMEOUT_MS = 60_000L
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
        /** Bundle 317 (G7): a files step. */
        val files: Boolean = false,
        /** Bundle 321 (N1, pick B): the card has no buttons - always false. */
        val stopButton: Boolean = false,
    )

    /** Bundle 317 (G7): the most trip segments on the track. */
    const val MAX_TRIPS = 7
    /** Bundle 317 (G7): "Stop files" comes back to Dart as this id prefix. */
    const val STOP_PREFIX = "stop317:"

    /** Bundle 317 (G7): equal trip pieces (1..7). */
    fun tripSegments(trips: Int): List<Int> {
        val n = trips.coerceIn(1, MAX_TRIPS)
        val base = 100 / n
        return List(n) { i -> if (i == n - 1) 100 - base * (n - 1) else base }
    }

    /** Bundle 314 (3): how far the tracker rocks and how often. */
    const val ROCK_STEP = 4
    const val ROCK_EVERY_MS = 3_000L

    fun plan(step: String, progress: Int, buzz: Boolean, swipe: Boolean = false): Plan {
        val p = progress.coerceIn(0, 100)
        return when (step) {
            // Bundle 317 (G7): files after Ready (the one buzz only if Ready was never posted).
            "files" -> Plan("files", p, false, ongoing = true, promoted = true, timeoutMs = 0,
                openButton = false, grey = false, readyPointGreen = true,
                channel = if (buzz) READY_CHANNEL_ID else CHANNEL_ID, alert = buzz, files = true)
            "files_wait" -> Plan("files_wait", p, false, ongoing = !swipe, promoted = !swipe, timeoutMs = 0,
                openButton = false, grey = false, readyPointGreen = true,
                channel = if (buzz) READY_CHANNEL_ID else CHANNEL_ID, alert = buzz, compatSliding = true,
                files = true)
            "files_done" -> Plan("files_done", 100, false, ongoing = false, promoted = false, timeoutMs = 0,
                openButton = false, grey = false, readyPointGreen = true,
                channel = if (buzz) READY_CHANNEL_ID else CHANNEL_ID, alert = buzz, files = true)
            "ready" -> Plan("ready", 100, false, ongoing = false, promoted = false, timeoutMs = 0,
                openButton = false, grey = false, readyPointGreen = true,
                channel = if (buzz) READY_CHANNEL_ID else CHANNEL_ID, alert = buzz)
            // Bundle 318 (K7): new only, nothing new - green like Ready, never buzzes, goes by itself.
            "up_to_date" -> Plan("up_to_date", 100, false, ongoing = false, promoted = false,
                timeoutMs = UP_TO_DATE_TIMEOUT_MS, openButton = false, grey = false, readyPointGreen = true,
                channel = CHANNEL_ID, alert = false)
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

    /** API 36+ draws the Live Update (ProgressStyle); below = [ChatCard321]. */
    fun useProgressStyle(sdk: Int): Boolean = sdk >= 36

    /** Bundle 321 (N2): Android keeps at most 10 segments and 4 points. */
    const val MAX_SEGMENTS_321 = 10
    const val MAX_POINTS_321 = 4

    /** Bundle 321 (N2/N3): the bar of one card - the same on every Android. */
    data class Bar321(
        val show: Boolean,
        val segments: List<Int>,
        val points: List<Int>,
        val progress: Int,
        val color: Int,
        val pointColor: Int,
        /** ring / wait / photo / video / voice / file */
        val tracker: String,
        val startLetter: String,
        val startColor: Int,
    )

    /** "100,40,0" from Dart -> one fill 0-100 per file. */
    fun fills321(pieces: String): List<Int> =
        pieces.split(',').mapNotNull { it.trim().toIntOrNull()?.coerceIn(0, 100) }

    /** Equal pieces that add up to 100: one per file, at most 10. */
    fun segments321(files: Int): List<Int> {
        val n = files.coerceIn(1, MAX_SEGMENTS_321)
        val base = 100 / n
        return List(n) { i -> if (i == n - 1) 100 - base * (n - 1) else base }
    }

    /** A green point at the end of each file that is in (the last 4; never at 0 / 100). */
    fun points321(fills: List<Int>): List<Int> {
        val n = fills.size
        if (n < 2) return emptyList()
        val done = fills.takeWhile { it >= 100 }.size
        return (1..done).filter { it < n }.map { it * 100 / n }.takeLast(MAX_POINTS_321)
    }

    /** Where the tracker stands: the average fill of the files. */
    fun progress321(fills: List<Int>, fallback: Int): Int =
        if (fills.isEmpty()) fallback.coerceIn(0, 100) else (fills.sum().toDouble() / fills.size).toInt().coerceIn(0, 100)

    fun tracker321(plan: Plan, kind: String): String = when {
        plan.step == "files_wait" || plan.step == "sent" || plan.step == "reached" -> "wait"
        plan.files -> when (kind) { "video", "voice", "file" -> kind; else -> "photo" }
        else -> "ring"
    }

    /** Ready / all files here / up to date / ended: only the line, no bar. */
    fun showBar321(plan: Plan): Boolean =
        !plan.grey && plan.step != "ready" && plan.step != "files_done" && plan.step != "up_to_date"

    fun bar321(plan: Plan, pieces: String, kind: String, from: String, at: Int): Bar321 {
        val color = trackerColor(plan)
        val fills = if (plan.files) fills321(pieces) else emptyList()
        return Bar321(
            show = showBar321(plan),
            segments = if (plan.files) segments321(fills.size) else listOf(100),
            points = if (plan.files) points321(fills) else POINTS.filter { it < 100 },
            progress = if (plan.files) progress321(fills, plan.progress) else at.coerceIn(0, 100),
            color = color,
            pointColor = if (plan.files) GREEN else color,
            tracker = tracker321(plan, kind),
            startLetter = if (from.isBlank()) "" else initialOf(from),
            startColor = colorOf(from),
        )
    }

    /** The green check at the end of the line (index, or -1). */
    fun checkAt321(title: String): Int = if (title.endsWith("\u2713")) title.length - 1 else -1

    /** The line with its check in green (the same on every phone). */
    fun title321(title: String): CharSequence {
        val at = checkAt321(title)
        if (at < 0) return title
        return android.text.SpannableString(title).apply {
            setSpan(android.text.style.ForegroundColorSpan(GREEN), at, at + 1, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(android.text.style.StyleSpan(android.graphics.Typeface.BOLD), at, at + 1, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    fun trackerRes321(tracker: String): Int = when (tracker) {
        "wait" -> R.drawable.ic_req321_wait
        "video" -> R.drawable.ic_req321_video
        "voice" -> R.drawable.ic_req321_mic
        "file" -> R.drawable.ic_req321_doc
        "photo" -> R.drawable.ic_req317_file
        else -> R.drawable.ic_req314_tracker
    }

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
        plan.step == "ready" || plan.step == "files_done" || plan.step == "up_to_date" -> GREEN
        plan.step == "files_wait" -> ORANGE
        plan.step == "files" -> BLUE
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
        val step = plan((args["step"] as? String).orEmpty(), (args["progress"] as? Number)?.toInt() ?: 0, false,
            args["files_swipe"] == true)
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
        val plan = plan((args["step"] as? String).orEmpty(), (args["progress"] as? Number)?.toInt() ?: 0, args["buzz"] == true,
            args["files_swipe"] == true)
        val title = (args["title"] as? String)?.trim().orEmpty()
        val short = (args["short"] as? String)?.trim().orEmpty()
        val faces = (args["names"] as? List<*>)?.mapNotNull { (it as? String)?.trim()?.takeIf { s -> s.isNotEmpty() } }.orEmpty()
        val from = (args["from_name"] as? String)?.trim().orEmpty()
        val whenMs = (args["when"] as? Number)?.toLong()?.takeIf { it > 0 } ?: System.currentTimeMillis()
        val open = PendingIntent.getActivity(
            context,
            requestCode(id, 0),
            tapIntent(context, id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Bundle 321 (N1/N2): the picture of the file coming, else the faces.
        val picture = thumb321((args["files_thumb"] as? String).orEmpty()) ?: facesIcon(faces)
        val bar = bar321(plan, (args["files_pieces"] as? String).orEmpty(), (args["files_kind"] as? String).orEmpty(), from,
            rockProgress(plan.progress, tick))
        // Same rule as useProgressStyle(); written out so Android lint sees the API check.
        val notification = if (Build.VERSION.SDK_INT >= 36) {
            buildLive(context, plan, title321(title), short, picture, whenMs, open, bar)
        } else {
            ChatCard321.build(context, plan, title, picture, whenMs, open, bar)
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
        title: CharSequence,
        short: String,
        picture: Bitmap?,
        whenMs: Long,
        open: PendingIntent,
        bar: Bar321,
    ): Notification {
        val b = Notification.Builder(context, plan.channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(BLUE)
            .setContentTitle(title)
            .setOngoing(plan.ongoing)
            .setOnlyAlertOnce(!plan.alert)
            .setWhen(whenMs)
            .setShowWhen(true)
            .setGroup(GROUP_KEY)
            .setGroupAlertBehavior(Notification.GROUP_ALERT_CHILDREN)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(open)
            .setAutoCancel(plan.step == "ready" || plan.step == "files_done")
            .setPublicVersion(
                Notification.Builder(context, plan.channel)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setColor(BLUE)
                    .setContentTitle(title)
                    .build(),
            )
        if (bar.show) b.setStyle(progressStyle321(context, bar))
        if (picture != null) b.setLargeIcon(picture)
        if (short.isNotEmpty() && plan.ongoing) b.setShortCriticalText(short)
        if (plan.timeoutMs > 0) b.setTimeoutAfter(plan.timeoutMs)
        if (plan.step == "up_to_date") b.setAutoCancel(true) // Bundle 318 (K7)
        if (plan.promoted) b.extras.putBoolean(EXTRA_PROMOTED, true)
        return b.build()
    }

    /** Bundle 321 (N2): one segment per file, green points, the tracker =
     *  the kind of file coming, start = the sender's letter, end = the check.
     *  Bundle 314 (3, pick B): Sent / Reached keep the bubble start and the
     *  rocking tracker (now the hourglass). */
    @RequiresApi(36)
    private fun progressStyle321(context: Context, bar: Bar321): Notification.ProgressStyle {
        val style = Notification.ProgressStyle()
            .setStyledByProgress(true) // filled up to the tracker
            .setProgressSegments(bar.segments.map { Notification.ProgressStyle.Segment(it).setColor(bar.color) })
            .setProgressPoints(bar.points.map { Notification.ProgressStyle.Point(it).setColor(bar.pointColor) })
            .setProgressTrackerIcon(Icon.createWithResource(context, trackerRes321(bar.tracker)).setTint(bar.color))
            .setProgressEndIcon(Icon.createWithResource(context, R.drawable.ic_req314_end))
            .setProgress(bar.progress)
            .setProgressIndeterminate(false)
        val letter = if (bar.startLetter.isEmpty()) null else ChatCard321.letterBitmap(bar.startLetter, bar.startColor, 96)
        if (letter != null) style.setProgressStartIcon(Icon.createWithBitmap(letter))
        else style.setProgressStartIcon(Icon.createWithResource(context, R.drawable.ic_req314_start))
        return style
    }

    /** Bundle 321 (N1): the small picture Dart sends (base64), or null. */
    private fun thumb321(b64: String): Bitmap? {
        if (b64.isEmpty()) return null
        return try {
            val bytes = android.util.Base64.decode(b64, android.util.Base64.DEFAULT)
            android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { ChatCard321.roundSquare(it, 192) }
        } catch (_: Throwable) {
            null
        }
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
