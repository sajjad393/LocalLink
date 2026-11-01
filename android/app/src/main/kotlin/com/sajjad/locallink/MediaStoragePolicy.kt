package com.sajjad.locallink

/**
 * Bundle 197b: pure rules for the media storage helpers (no Android types,
 * unit-tested on the JVM).
 */
object MediaStoragePolicy {
    /** Longest side of our small picture. */
    const val THUMB_PX = 320
    const val THUMB_QUALITY = 70

    /** BitmapFactory inSampleSize (power of two) so the decoded picture is
     *  still at least [maxPx] on its longest side - never the full 12 MP. */
    fun sampleSize(width: Int, height: Int, maxPx: Int = THUMB_PX): Int {
        if (width <= 0 || height <= 0 || maxPx <= 0) return 1
        var sample = 1
        val longest = maxOf(width, height)
        while (longest / (sample * 2) >= maxPx) sample *= 2
        return sample
    }

    /** Final size for the longest side [maxPx] (keeps the shape). */
    fun scaled(width: Int, height: Int, maxPx: Int = THUMB_PX): Pair<Int, Int> {
        if (width <= 0 || height <= 0) return Pair(0, 0)
        val longest = maxOf(width, height)
        if (longest <= maxPx) return Pair(width, height)
        val scale = maxPx.toDouble() / longest
        return Pair(maxOf(1, Math.round(width * scale).toInt()), maxOf(1, Math.round(height * scale).toInt()))
    }

    /** EXIF orientation -> degrees to rotate. */
    fun exifDegrees(orientation: Int): Int = when (orientation) {
        6 -> 90
        3 -> 180
        8 -> 270
        else -> 0
    }

    /** Where "Save to phone" puts a file: photos and videos in the Gallery
     *  (Pictures/LinkUp), everything else in Download/LinkUp. */
    fun saveFolder(mime: String): String {
        val m = mime.lowercase()
        return if (m.startsWith("image/") || m.startsWith("video/")) "Pictures/LinkUp" else "Download/LinkUp"
    }

    fun saveKind(mime: String): String {
        val m = mime.lowercase()
        return when {
            m.startsWith("image/") -> "photo"
            m.startsWith("video/") -> "video"
            else -> "document"
        }
    }

    /** Safe display name for MediaStore (no path parts). */
    fun safeName(name: String): String {
        val base = name.substringAfterLast('/').substringAfterLast('\\').trim()
        val cleaned = base.replace(Regex("[\\u0000-\\u001f:*?\"<>|]"), "_")
        return if (cleaned.isEmpty() || cleaned == "." || cleaned == "..") "LinkUp_file" else cleaned.take(120)
    }

    /** Used storage in whole percent (0-100). */
    fun usedPercent(total: Long, free: Long): Int {
        if (total <= 0L) return 0
        val used = (total - free.coerceIn(0L, total)).toDouble() / total
        return Math.round(used * 100).toInt().coerceIn(0, 100)
    }
}
