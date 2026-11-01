package com.sajjad.locallink

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.NotificationManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Bundle 185 (A1, A2, A3, B1): the Android side. */
object AppHealth {
    private const val PREFS = "linkup_health"
    private const val SEEN_KEY = "exit_seen_ms"
    private val exitsLogged = AtomicBoolean(false)
    private val watcherStarted = AtomicBoolean(false)
    @Volatile private var openedAt = 0L
    private val acked = AtomicLong(0L)
    private var lastStallLogAt = 0L
    // Bundle 187 (A2): the last main-thread stall (300 ms+), for slow storage notes.
    @Volatile private var lastStallEnd = 0L
    @Volatile private var lastStallMs = 0L

    // Bundle 188 (B3): what LinkUp is doing now, kept by Android with the process.
    @Volatile private var appContext: Context? = null
    private val stateLock = Any()
    private var noteCall = false
    private var noteFilesIn = 0
    private var noteFilesOut = 0
    private var noteFileAtS = 0L
    private var lastNote: String? = null

    /** B3: a call started / ended. */
    fun noteCall(on: Boolean) {
        synchronized(stateLock) { noteCall = on }
        publishState()
    }

    /** B3: file counts now; [active] = a file moved just now. */
    fun noteFiles(filesIn: Int, filesOut: Int, active: Boolean) {
        synchronized(stateLock) {
            noteFilesIn = filesIn; noteFilesOut = filesOut
            if (active) noteFileAtS = System.currentTimeMillis() / 1000L
        }
        publishState()
    }

    private fun publishState() {
        if (Build.VERSION.SDK_INT < 30) return
        val app = appContext ?: return
        val note = synchronized(stateLock) {
            if (!ProcessStateNote.shouldWrite(lastNote, noteCall, noteFilesIn, noteFilesOut, noteFileAtS)) return
            ProcessStateNote.summary(noteCall, noteFilesIn, noteFilesOut, noteFileAtS).also { lastNote = it }
        }
        try {
            val am = app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.setProcessStateSummary(note.toByteArray(Charsets.US_ASCII).copyOf(minOf(note.length, ProcessStateNote.MAX_BYTES)))
        } catch (_: Throwable) {}
    }

    /** Bundle 187 (A2): did a stall overlap the last [windowMs]? "y" / "n" / "-" (not watched). */
    fun stallOverlap(windowMs: Long): String {
        val now = SystemClock.elapsedRealtime()
        return StallRules.overlap(now, windowMs, lastStallEnd, lastStallMs,
            StallRules.watching(now, openedAt, CallNearbyPause.inCall()))
    }

    /** A1: why did LinkUp stop last time? Once per process, off the main thread. */
    fun logExitsOnce(context: Context) {
        if (Build.VERSION.SDK_INT < 30) return
        if (!exitsLogged.compareAndSet(false, true)) return
        val app = context.applicationContext
        // Bundle 188 (B3): start this process with a "doing nothing" note.
        appContext = app
        publishState()
        Thread({
            try {
                val am = app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val list: List<ApplicationExitInfo> = am.getHistoricalProcessExitReasons(app.packageName, 0, 10)
                val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val seen = prefs.getLong(SEEN_KEY, 0L)
                val fresh = AppHealthPolicy.newExits(list.map { it.timestamp }, seen)
                val now = System.currentTimeMillis()
                for (ts in fresh) {
                    val e = list.firstOrNull { it.timestamp == ts } ?: continue
                    val note = try { e.processStateSummary?.toString(Charsets.US_ASCII) } catch (_: Throwable) { null }
                    Log.w(AppHealthPolicy.TAG, AppHealthPolicy.exitLine(e.reason, e.importance, e.timestamp, now, e.pss, e.rss, e.description,
                        ProcessStateNote.doing(note, e.timestamp)))
                }
                val newest = list.maxOfOrNull { it.timestamp } ?: 0L
                if (newest > seen) prefs.edit().putLong(SEEN_KEY, newest).apply()
                if (fresh.isEmpty()) Log.i(AppHealthPolicy.TAG, "APP_LAST_EXIT none_new")
            } catch (t: Throwable) {
                Log.w(AppHealthPolicy.TAG, "APP_LAST_EXIT failed=${t.javaClass.simpleName}")
            }
        }, "linkup-exit-info").apply { isDaemon = true }.start()
    }

    /** A2: what Android lets LinkUp do right now. */
    fun logKeepAlive(context: Context, moment: String) {
        val app = context.applicationContext
        Thread({
            val battery = try {
                (app.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(app.packageName)
            } catch (_: Throwable) { null }
            val am = app.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val restricted = if (Build.VERSION.SDK_INT >= 28) try { am?.isBackgroundRestricted } catch (_: Throwable) { null } else false
            val bucket = if (Build.VERSION.SDK_INT >= 28) try {
                (app.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager)?.appStandbyBucket
            } catch (_: Throwable) { null } else null
            val notifications = try {
                (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
            } catch (_: Throwable) { null }
            Log.i(AppHealthPolicy.TAG, AppHealthPolicy.keepAliveLine(moment, battery, restricted, bucket, notifications,
                LocalLinkTransportService.isRunning(), Build.MANUFACTURER ?: ""))
        }, "linkup-keep-alive").apply { isDaemon = true }.start()
    }

    /** B1: Android asks for memory. Returns true when caches should be freed. */
    fun onTrim(level: Int): Boolean {
        val free = AppHealthPolicy.shouldFreeCaches(level)
        Log.i(AppHealthPolicy.TAG, "MEMORY_TRIM level=${AppHealthPolicy.trimName(level)} code=$level free_caches=${if (free) "y" else "n"}")
        return free
    }

    /** A3: the app screen opened - watch the main thread for 2 minutes. */
    fun appOpened() {
        openedAt = SystemClock.elapsedRealtime()
        startWatcher()
    }

    /** A3: a call started - make sure the watcher runs. */
    fun startWatcher() {
        if (!watcherStarted.compareAndSet(false, true)) return
        val main = Handler(Looper.getMainLooper())
        val mainThread = Looper.getMainLooper().thread
        Thread({
            var seq = 0L
            while (true) {
                try {
                    val now = SystemClock.elapsedRealtime()
                    if (!StallRules.watching(now, openedAt, CallNearbyPause.inCall())) {
                        Thread.sleep(1_000L)
                        continue
                    }
                    val mine = ++seq
                    val postedAt = now
                    main.post { acked.set(mine) }
                    Thread.sleep(StallRules.TICK_MS)
                    if (acked.get() >= mine) continue
                    var frames: List<String> = emptyList()
                    while (acked.get() < mine) {
                        Thread.sleep(50L)
                        if (frames.isEmpty() && SystemClock.elapsedRealtime() - postedAt >= StallRules.STALL_MS) {
                            frames = try { mainThread.stackTrace.map { it.toString() } } catch (_: Throwable) { emptyList() }
                        }
                        if (SystemClock.elapsedRealtime() - postedAt > 60_000L) break // gave up waiting
                    }
                    val end = SystemClock.elapsedRealtime()
                    val stall = end - postedAt
                    if (stall >= StallRules.NOTE_MS) { lastStallMs = stall; lastStallEnd = end }
                    if (StallRules.shouldLog(stall, end, lastStallLogAt)) {
                        lastStallLogAt = end
                        val when_ = if (CallNearbyPause.inCall()) "call" else "open"
                        Log.w(AppHealthPolicy.TAG, "MAIN_STALL ms=$stall during=$when_ at=${StallRules.describe(frames)}")
                    }
                } catch (_: InterruptedException) {
                    return@Thread
                } catch (_: Throwable) {
                    try { Thread.sleep(1_000L) } catch (_: InterruptedException) { return@Thread }
                }
            }
        }, "linkup-stall-watch").apply { isDaemon = true; priority = Thread.MIN_PRIORITY + 1 }.start()
    }
}
