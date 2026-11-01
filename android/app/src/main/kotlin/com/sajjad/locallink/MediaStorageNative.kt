package com.sajjad.locallink

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * Bundle 197b: media storage helpers for the Dart side (channel
 * `locallink/voice_notes`): small pictures, phone storage numbers, Gallery
 * links (persistable URI grants) and Save to phone (MediaStore).
 * Every call runs off the UI thread in MainActivity.
 */
object MediaStorageNative {
    private fun inDataDir(context: Context, file: File): Boolean = try {
        val dataDir = File(context.applicationInfo.dataDir).canonicalPath
        file.canonicalPath.startsWith(dataDir + File.separator)
    } catch (_: Exception) { false }

    /** Small JPEG of a photo or a video frame. Returns duration_ms for videos. */
    fun makeThumb(context: Context, input: String, output: String, isVideo: Boolean, maxPx: Int): Map<String, Any> {
        val inFile = File(input)
        val outFile = File(output)
        require(inFile.isFile && inDataDir(context, inFile) && inDataDir(context, outFile)) { "invalid file" }
        var durationMs = 0L
        var bitmap: Bitmap? = null
        if (isVideo) {
            val r = MediaMetadataRetriever()
            try {
                r.setDataSource(inFile.absolutePath)
                durationMs = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                bitmap = if (Build.VERSION.SDK_INT >= 27)
                    r.getScaledFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, maxPx, maxPx)
                else r.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                if (bitmap == null || isDark(bitmap)) {
                    for (us in VideoFramePolicy.retryTimesUs(durationMs)) {
                        val next = r.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: continue
                        if (!isDark(next)) { bitmap?.recycle(); bitmap = next; break }
                        next.recycle()
                    }
                }
            } finally { try { r.release() } catch (_: Exception) {} }
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(inFile.absolutePath, bounds)
            val opts = BitmapFactory.Options().apply {
                inSampleSize = MediaStoragePolicy.sampleSize(bounds.outWidth, bounds.outHeight, maxPx)
            }
            bitmap = BitmapFactory.decodeFile(inFile.absolutePath, opts)
            val degrees = try {
                MediaStoragePolicy.exifDegrees(ExifInterface(inFile.absolutePath)
                    .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL))
            } catch (_: Exception) { 0 }
            val b0 = bitmap
            if (b0 != null && degrees != 0) {
                val m = Matrix().apply { postRotate(degrees.toFloat()) }
                val rotated = Bitmap.createBitmap(b0, 0, 0, b0.width, b0.height, m, true)
                if (rotated !== b0) b0.recycle()
                bitmap = rotated
            }
        }
        val b = bitmap ?: throw IllegalStateException("no picture")
        val (w, h) = MediaStoragePolicy.scaled(b.width, b.height, maxPx)
        val small = if (w != b.width || h != b.height) Bitmap.createScaledBitmap(b, w, h, true) else b
        outFile.parentFile?.mkdirs()
        FileOutputStream(outFile).use { small.compress(Bitmap.CompressFormat.JPEG, MediaStoragePolicy.THUMB_QUALITY, it) }
        if (small !== b) small.recycle()
        b.recycle()
        return mapOf("duration_ms" to durationMs, "bytes" to outFile.length(), "width" to w, "height" to h)
    }

    private fun isDark(b: Bitmap): Boolean = try {
        var sum = 0L; var n = 0
        val stepX = maxOf(1, b.width / 8); val stepY = maxOf(1, b.height / 8)
        var y = 0
        while (y < b.height) { var x = 0; while (x < b.width) { val c = b.getPixel(x, y); sum += ((c shr 16) and 255) + ((c shr 8) and 255) + (c and 255); n++; x += stepX }; y += stepY }
        n > 0 && sum / (n * 3) < 12
    } catch (_: Exception) { false }

    fun storageStats(): Map<String, Any> {
        val stat = StatFs(Environment.getDataDirectory().path)
        val total = stat.blockCountLong * stat.blockSizeLong
        val free = stat.availableBlocksLong * stat.blockSizeLong
        return mapOf("total" to total, "free" to free, "used_percent" to MediaStoragePolicy.usedPercent(total, free))
    }

    /** Picker: keep read access to the picked file (survives restarts). */
    fun keepLink(context: Context, uri: Uri): Boolean = try {
        context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        true
    } catch (_: Exception) { false }

    fun linkCount(context: Context): Int = try { context.contentResolver.persistedUriPermissions.size } catch (_: Exception) { 0 }

    fun uriAlive(context: Context, value: String): Boolean = try {
        val uri = Uri.parse(value)
        val held = context.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
        held && (context.contentResolver.openFileDescriptor(uri, "r")?.use { true } ?: false)
    } catch (_: Exception) { false }

    fun releaseLinks(context: Context, values: List<String>): Int {
        var n = 0
        for (v in values) {
            try {
                context.contentResolver.releasePersistableUriPermission(Uri.parse(v), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                n++
            } catch (_: Exception) {}
        }
        return n
    }

    /** Copy a Gallery file back into LinkUp (sender tap on removed media). */
    fun restoreFromUri(context: Context, value: String, output: String): Long {
        val out = File(output)
        require(inDataDir(context, out)) { "invalid file" }
        out.parentFile?.mkdirs()
        val tmp = File(out.absolutePath + ".restore")
        context.contentResolver.openInputStream(Uri.parse(value)).use { input ->
            requireNotNull(input) { "gone" }
            FileOutputStream(tmp).use { input.copyTo(it) }
        }
        if (!tmp.renameTo(out)) { tmp.copyTo(out, overwrite = true); tmp.delete() }
        return out.length()
    }

    /** Save to phone (Android 10+, no permission): returns the content uri. */
    fun saveToPhone(context: Context, path: String, name: String, mime: String): String {
        require(Build.VERSION.SDK_INT >= 29) { "android_10_needed" }
        val src = File(path)
        require(src.isFile && inDataDir(context, src)) { "invalid file" }
        val resolver = context.contentResolver
        val folder = MediaStoragePolicy.saveFolder(mime)
        val collection = when (MediaStoragePolicy.saveKind(mime)) {
            "photo" -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            "video" -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            else -> MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, MediaStoragePolicy.safeName(name))
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: throw IllegalStateException("insert_failed")
        try {
            resolver.openOutputStream(uri).use { out ->
                requireNotNull(out) { "open_failed" }
                FileInputStream(src).use { it.copyTo(out) }
            }
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            try { resolver.delete(uri, null, null) } catch (_: Exception) {}
            throw e
        }
        return uri.toString()
    }

    /** The saved copy still exists (receiver tap on removed media). */
    fun savedAlive(context: Context, value: String): Boolean = try {
        context.contentResolver.openFileDescriptor(Uri.parse(value), "r")?.use { true } ?: false
    } catch (_: Exception) { false }

    /** Open a Gallery / saved copy in the phone's own viewer. */
    fun openUri(context: Context, value: String, mime: String): Boolean = try {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(value), mime.ifEmpty { "*/*" })
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        true
    } catch (_: Exception) { false }
}
