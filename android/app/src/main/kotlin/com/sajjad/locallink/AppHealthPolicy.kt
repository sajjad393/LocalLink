package com.sajjad.locallink

/**
 * Bundle 185 (A): plain facts about why LinkUp stopped and how it starts.
 * Pure rules here (tested on the PC); Android calls in [AppHealth].
 */
object AppHealthPolicy {
    const val TAG = "LinkUpHealth"
    const val MAX_EXITS = 3

    /** ApplicationExitInfo.REASON_* in plain words. */
    fun reasonName(code: Int): String = when (code) {
        1 -> "app_exit"
        2 -> "signal"
        3 -> "low_memory"
        4 -> "crash"
        5 -> "native_crash"
        6 -> "not_responding"
        7 -> "start_failed"
        8 -> "permission_change"
        9 -> "too_much_battery_or_cpu"
        10 -> "force_stop" // user, Settings, or a phone tool like ZTE SuperKiller
        11 -> "user_stopped"
        12 -> "dependency_died"
        13 -> "other"
        14 -> "frozen"
        15 -> "package_state_change"
        16 -> "app_updated"
        else -> "unknown"
    }

    /** RunningAppProcessInfo.IMPORTANCE_* at the moment of death. */
    fun importanceName(code: Int): String = when {
        code <= 100 -> "open"
        code <= 125 -> "service"          // foreground service (Keep running)
        code <= 230 -> "visible"
        code <= 300 -> "background_service"
        code <= 400 -> "cached"
        else -> "gone"
    }

    /** One line per death. [description] is the phone's own text (ZTE often adds one). */
    fun exitLine(reason: Int, importance: Int, atMs: Long, nowMs: Long, pssKb: Long, rssKb: Long, description: String?,
                 doing: String? = null): String {
        val ago = ((nowMs - atMs).coerceAtLeast(0L)) / 1000L
        val clean = (description ?: "").replace(Regex("[\\r\\n\\t]+"), " ").trim().take(120)
        // Bundle 188 (B3): what LinkUp was doing at that moment (call / file).
        val doingPart = if (doing == null) "" else "doing=$doing "
        return "APP_LAST_EXIT reason=${reasonName(reason)} code=$reason was=${importanceName(importance)} " +
            "ago_s=$ago mem_mb=${pssKb / 1024} rss_mb=${rssKb / 1024} " + doingPart +
            "text=${if (clean.isEmpty()) "-" else clean}"
    }

    /** Deaths newer than [seenMs], oldest first, max [max]. */
    fun newExits(timestamps: List<Long>, seenMs: Long, max: Int = MAX_EXITS): List<Long> =
        timestamps.filter { it > seenMs }.sortedDescending().take(max).sorted()

    fun bucketName(bucket: Int): String = when (bucket) {
        5 -> "exempted"
        10 -> "active"
        20 -> "working_set"
        30 -> "frequent"
        40 -> "rare"
        45 -> "restricted"
        50 -> "never"
        else -> "-"
    }

    fun keepAliveLine(moment: String, batteryUnrestricted: Boolean?, backgroundRestricted: Boolean?, bucket: Int?,
                      notifications: Boolean?, service: Boolean, brand: String): String {
        fun yn(v: Boolean?) = when (v) { true -> "y"; false -> "n"; null -> "-" }
        val battery = when (batteryUnrestricted) { true -> "unrestricted"; false -> "optimized"; null -> "-" }
        return "KEEP_ALIVE_STATE when=$moment battery=$battery bg_restricted=${yn(backgroundRestricted)} " +
            "bucket=${bucket?.let { bucketName(it) } ?: "-"} notifications=${yn(notifications)} " +
            "service=${yn(service)} brand=${brand.lowercase().ifBlank { "-" }}"
    }

    /** Android's onTrimMemory levels in plain words. */
    fun trimName(level: Int): String = when {
        level >= 80 -> "complete"      // TRIM_MEMORY_COMPLETE: next in line to be killed
        level >= 60 -> "moderate"
        level >= 40 -> "background"
        level >= 20 -> "ui_hidden"
        level >= 15 -> "running_critical"
        level >= 10 -> "running_low"
        level >= 5 -> "running_moderate"
        else -> "other"
    }

    /** Free picture caches only when it helps: app hidden and Android asks for memory. */
    fun shouldFreeCaches(level: Int): Boolean = level >= 40 || level in 10..15
}

/**
 * Bundle 185 (A3): the main thread runs Android AND Dart (Flutter 3.32+).
 * A watcher thread pings it every 100 ms. When it is stuck for 700 ms or more,
 * one MAIN_STALL line says how long and which code was running.
 */
object StallRules {
    const val TICK_MS = 100L
    const val STALL_MS = 700L
    const val MIN_GAP_MS = 5_000L
    const val WATCH_AFTER_OPEN_MS = 120_000L
    /** Bundle 187 (A2): stalls this long are remembered for slow storage notes (not logged). */
    const val NOTE_MS = 300L

    /**
     * Bundle 187 (A2): "y" when the last stall [stallEnd - stallMs, stallEnd]
     * touches the last [windowMs]; else "n" if the watcher runs now; else "-".
     */
    fun overlap(now: Long, windowMs: Long, stallEnd: Long, stallMs: Long, watchingNow: Boolean): String {
        if (stallEnd > 0L && stallMs > 0L) {
            val stallStart = stallEnd - stallMs
            val windowStart = now - windowMs.coerceAtLeast(0L)
            if (stallEnd >= windowStart && stallStart <= now) return "y"
        }
        return if (watchingNow) "n" else "-"
    }

    /** Watch only in the first 2 minutes after open, and during calls. */
    fun watching(now: Long, openedAt: Long, inCall: Boolean): Boolean =
        inCall || (openedAt > 0L && now - openedAt in 0 until WATCH_AFTER_OPEN_MS)

    fun shouldLog(stallMs: Long, now: Long, lastLogAt: Long): Boolean =
        stallMs >= STALL_MS && (lastLogAt == 0L || now - lastLogAt >= MIN_GAP_MS)

    /**
     * The top code lines at the stall. If the main thread was only waiting for
     * messages, the time went into Dart (or the Flutter engine), not Android code.
     */
    fun describe(frames: List<String>): String {
        if (frames.isEmpty()) return "-"
        val top = frames.first()
        if (top.contains("MessageQueue.nativePollOnce")) return "dart_or_engine"
        return frames.take(5).joinToString("<") { shortFrame(it) }
    }

    private fun shortFrame(frame: String): String {
        // "com.foo.Bar.baz(Bar.kt:12)" -> "Bar.baz:12"
        val name = frame.substringBefore('(')
        val parts = name.split('.')
        val cls = if (parts.size >= 2) parts[parts.size - 2] else name
        val method = parts.lastOrNull() ?: ""
        val line = frame.substringAfterLast(':', "").substringBefore(')')
        return if (line.isNotEmpty() && line.all { it.isDigit() }) "$cls.$method:$line" else "$cls.$method"
    }
}

/**
 * Bundle 188 (B3): what LinkUp was doing when it was killed.
 *
 * Android keeps a tiny note per process (setProcessStateSummary, max 128
 * bytes) and hands it back with the exit record after a death. The note is
 * written only when something changes (call on/off, file counts) or file
 * activity moved on by 10 s, so it costs almost nothing.
 */
object ProcessStateNote {
    const val MAX_BYTES = 128
    /** A file counts as "running" if it moved in the last 60 s before the death. */
    const val FILE_RECENT_S = 60L
    const val REFRESH_S = 10L

    fun summary(inCall: Boolean, filesIn: Int, filesOut: Int, fileActivityS: Long): String =
        "v1 call=${if (inCall) 1 else 0} fin=${filesIn.coerceIn(0, 99)} fout=${filesOut.coerceIn(0, 99)} fat=${fileActivityS.coerceAtLeast(0L)}"

    /** Plain words for the exit line: "call", "file_in", "call+file_out", "none", or "-" (no note). */
    fun doing(note: String?, exitAtMs: Long): String {
        if (note.isNullOrBlank() || !note.startsWith("v1 ")) return "-"
        val map = note.trim().split(' ').drop(1).mapNotNull {
            val i = it.indexOf('=')
            if (i <= 0) null else it.substring(0, i) to it.substring(i + 1)
        }.toMap()
        val call = map["call"] == "1"
        val fin = map["fin"]?.toIntOrNull() ?: 0
        val fout = map["fout"]?.toIntOrNull() ?: 0
        val fat = map["fat"]?.toLongOrNull() ?: 0L
        val recent = fat > 0L && exitAtMs / 1000L - fat in 0..FILE_RECENT_S
        val parts = ArrayList<String>()
        if (call) parts.add("call")
        if (fin > 0 && recent) parts.add("file_in")
        if (fout > 0 && recent) parts.add("file_out")
        return if (parts.isEmpty()) "none" else parts.joinToString("+")
    }

    /** Write a new note? Only on a real change, or file activity 10 s newer. */
    fun shouldWrite(last: String?, inCall: Boolean, filesIn: Int, filesOut: Int, fileActivityS: Long): Boolean {
        if (last == null) return true
        val next = summary(inCall, filesIn, filesOut, fileActivityS)
        if (next == last) return false
        val lastFat = last.substringAfter("fat=", "0").toLongOrNull() ?: 0L
        val sameCounts = last.substringBefore(" fat=") == next.substringBefore(" fat=")
        return !sameCounts || fileActivityS - lastFat >= REFRESH_S
    }
}
