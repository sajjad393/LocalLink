package com.sajjad.locallink

/**
 * Bundle 180: rules for LinkUp's own log files (pure, unit-tested).
 * One file per 10 minutes; only the last hour is kept, max 10 MB in total.
 */
object LogFilePolicy {
    const val SLOT_MS = 10L * 60L * 1000L
    const val KEEP_MS = 60L * 60L * 1000L
    const val MAX_TOTAL_BYTES = 10L * 1024L * 1024L

    /** Slots kept besides the current one (an extra slot so a full hour always stays). */
    const val KEEP_SLOTS = (KEEP_MS / SLOT_MS).toInt()

    /** native-123.log, app-ui-123.log, app-bg-123.log */
    private val NAME = Regex("^(native|app-[a-z]+)-(\\d+)\\.log$")

    fun slotOf(epochMs: Long): Long = if (epochMs <= 0L) 0L else epochMs / SLOT_MS

    fun nativeFileName(slot: Long): String = "native-$slot.log"

    /** Slot from a log file name, or null if it is not one of ours. */
    fun slotFromName(name: String): Long? = NAME.matchEntire(name)?.groupValues?.get(2)?.toLongOrNull()

    data class LogFileInfo(val name: String, val slot: Long, val size: Long)

    /**
     * Names to delete: older than the kept hour, then the oldest until the
     * total is under [MAX_TOTAL_BYTES]. The current slot is never deleted.
     */
    fun filesToDelete(files: List<LogFileInfo>, nowSlot: Long): List<String> {
        val out = mutableListOf<String>()
        val keep = mutableListOf<LogFileInfo>()
        for (f in files) if (f.slot < nowSlot - KEEP_SLOTS) out += f.name else keep += f
        var total = keep.sumOf { it.size }
        for (f in keep.sortedBy { it.slot }) {
            if (total <= MAX_TOTAL_BYTES) break
            if (f.slot >= nowSlot) continue
            out += f.name
            total -= f.size
        }
        return out
    }

    /** Lines that are logcat noise, not log lines. */
    fun skipLine(line: String): Boolean = line.isBlank() || line.startsWith("--------- beginning of")

    /** Epoch seconds.millis at the start of a `logcat -v epoch` line ("1730460000.123"), or null. */
    fun epochOf(line: String): String? {
        val t = line.trimStart()
        val end = t.indexOf(' ')
        if (end <= 0) return null
        val v = t.substring(0, end)
        return if (v.matches(Regex("^\\d{9,11}\\.\\d{3}$"))) v else null
    }
}
