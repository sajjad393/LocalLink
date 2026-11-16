package com.sajjad.locallink

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat

/**
 * Bundle 321 (N3, USER PICK B "same look and feel for every phone as is
 * mock"): Android 15 and older have no ProgressStyle, so the chat request
 * card draws its own body - the same one line, the same piece bar (a
 * picture: start letter, one piece per file, green points, the tracker,
 * the check) and the same photo as Android 16 ([ChatRequestNotifier307]).
 * The frame, the "LinkUp · now" header and the corners come from the
 * phone's skin (DecoratedCustomViewStyle). No buttons; tap opens the chat.
 *
 * Kept apart from ChatRequestNotifier307: a promoted Live Update (16+) may
 * not have custom views, so that file never builds one.
 */
object ChatCard321 {
    fun build(
        context: Context,
        plan: ChatRequestNotifier307.Plan,
        title: String,
        picture: Bitmap?,
        whenMs: Long,
        open: PendingIntent,
        bar: ChatRequestNotifier307.Bar321,
    ): Notification {
        val line = ChatRequestNotifier307.title321(title)
        val b = NotificationCompat.Builder(context, plan.channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ChatRequestNotifier307.trackerColor(plan))
            .setContentTitle(line)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(body(context, line, picture, bar, 1))
            .setCustomBigContentView(body(context, line, picture, bar, 3))
            .setOngoing(plan.ongoing)
            .setOnlyAlertOnce(!plan.alert)
            .setWhen(whenMs)
            .setShowWhen(true)
            .setGroup(ChatRequestNotifier307.GROUP_KEY)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(open)
            .setAutoCancel(plan.step == "ready" || plan.step == "files_done")
            .setPublicVersion(
                NotificationCompat.Builder(context, plan.channel)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setColor(ChatRequestNotifier307.BLUE)
                    .setContentTitle(line)
                    .build(),
            )
        if (!plan.alert) b.setSilent(true)
        if (plan.alert && Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            // Below Android 8 there are no channels: the message tone only (no buzz permission).
            val soundId = context.resources.getIdentifier("locallink_message", "raw", context.packageName)
            if (soundId != 0) b.setSound(Uri.parse("android.resource://${context.packageName}/$soundId"))
        }
        if (plan.timeoutMs > 0) b.setTimeoutAfter(plan.timeoutMs)
        if (plan.step == "up_to_date") b.setAutoCancel(true) // Bundle 318 (K7)
        return b.build()
    }

    private fun body(context: Context, line: CharSequence, picture: Bitmap?, bar: ChatRequestNotifier307.Bar321, lines: Int): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.notif321_card)
        v.setTextViewText(R.id.n321_title, line)
        v.setInt(R.id.n321_title, "setMaxLines", lines)
        if (picture != null) v.setImageViewBitmap(R.id.n321_pic, picture)
        else v.setViewVisibility(R.id.n321_pic, android.view.View.GONE)
        val strip = if (bar.show) barBitmap(context, bar) else null
        if (strip != null) v.setImageViewBitmap(R.id.n321_bar, strip)
        else v.setViewVisibility(R.id.n321_bar, android.view.View.GONE)
        return v
    }

    /** The bar picture: about the width of the card body, 20 dp high. */
    fun barBitmap(context: Context, bar: ChatRequestNotifier307.Bar321): Bitmap? {
        return try {
            val dm = context.resources.displayMetrics
            val dp = dm.density
            // Screen minus the panel margins, the decorated card's padding and the 40 dp photo.
            val w = (dm.widthPixels.coerceAtMost(dm.heightPixels) - 140 * dp).toInt().coerceAtLeast((120 * dp).toInt())
            val h = (20 * dp).toInt()
            val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val c = Canvas(out)
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            val r = h / 2f
            val cy = h / 2f
            // Start: the sender's letter (or a plain dot in the card colour).
            val endR = r * 0.9f
            if (bar.startLetter.isNotEmpty()) {
                letterBitmap(bar.startLetter, bar.startColor, (endR * 2).toInt())?.let { c.drawBitmap(it, r - endR, cy - endR, null) }
            } else {
                p.color = bar.color
                c.drawCircle(r, cy, endR * 0.55f, p)
            }
            // End: the check in the card colour.
            p.color = bar.color
            c.drawCircle(w - r, cy, endR, p)
            glyph(context, R.drawable.ic_req314_end, w - r, cy, endR * 1.5f, Color.WHITE, c)
            // The pieces.
            val gap = 3 * dp
            val x0 = 2 * r + 6 * dp
            val x1 = w - 2 * r - 6 * dp
            val track = (x1 - x0).coerceAtLeast(1f)
            val lineH = 5 * dp
            val at = x0 + track * bar.progress / 100f
            var x = x0
            for ((i, seg) in bar.segments.withIndex()) {
                val sw = track * seg / 100f - if (i < bar.segments.size - 1) gap else 0f
                val rect = RectF(x, cy - lineH / 2, x + sw.coerceAtLeast(1f), cy + lineH / 2)
                p.color = (bar.color and 0x00FFFFFF) or 0x4D000000 // the part still to come
                c.drawRoundRect(rect, lineH / 2, lineH / 2, p)
                if (at > rect.left) {
                    p.color = bar.color
                    c.save()
                    c.clipRect(rect.left, rect.top, minOf(at, rect.right), rect.bottom)
                    c.drawRoundRect(rect, lineH / 2, lineH / 2, p)
                    c.restore()
                }
                x += track * seg / 100f
            }
            // Green points: a file is in.
            for (pt in bar.points) {
                val px = x0 + track * pt / 100f
                p.color = Color.WHITE
                c.drawCircle(px, cy, 3.6f * dp, p)
                p.color = bar.pointColor
                c.drawCircle(px, cy, 2.6f * dp, p)
            }
            // The tracker: the kind of file coming (hourglass while waiting).
            val tr = r * 0.95f
            val tx = at.coerceIn(x0 + tr, x1 - tr)
            p.color = Color.WHITE
            c.drawCircle(tx, cy, tr + 1.5f * dp, p)
            p.color = bar.color
            c.drawCircle(tx, cy, tr, p)
            glyph(context, ChatRequestNotifier307.trackerRes321(bar.tracker), tx, cy, tr * 1.2f, Color.WHITE, c)
            out
        } catch (_: Throwable) {
            null
        }
    }

    private fun glyph(context: Context, res: Int, cx: Float, cy: Float, size: Float, color: Int, c: Canvas) {
        val d = context.getDrawable(res)?.mutate() ?: return
        d.setTint(color)
        val half = (size / 2).toInt()
        d.bounds = Rect((cx - half).toInt(), (cy - half).toInt(), (cx + half).toInt(), (cy + half).toInt())
        d.draw(c)
    }

    /** A letter in a circle of the avatar colour (the start of the bar). */
    fun letterBitmap(letter: String, color: Int, size: Int): Bitmap? {
        if (size <= 0) return null
        return try {
            val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val c = Canvas(out)
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            p.color = color
            c.drawCircle(size / 2f, size / 2f, size / 2f, p)
            p.color = Color.WHITE
            p.textAlign = Paint.Align.CENTER
            p.typeface = Typeface.DEFAULT_BOLD
            p.textSize = size * 0.5f
            c.drawText(letter, size / 2f, size / 2f - (p.descent() + p.ascent()) / 2f, p)
            out
        } catch (_: Throwable) {
            null
        }
    }

    /** The photo: centre crop to a square with round corners. */
    fun roundSquare(src: Bitmap, size: Int): Bitmap {
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val side = minOf(src.width, src.height)
        val from = Rect((src.width - side) / 2, (src.height - side) / 2, (src.width + side) / 2, (src.height + side) / 2)
        val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val box = RectF(0f, 0f, size.toFloat(), size.toFloat())
        c.drawRoundRect(box, size * 0.18f, size * 0.18f, p)
        p.xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.SRC_IN)
        c.drawBitmap(src, from, box, p)
        return out
    }
}
