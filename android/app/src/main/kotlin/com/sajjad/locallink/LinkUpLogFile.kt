package com.sajjad.locallink

import android.content.Context
import android.os.Build
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bundle 180: LinkUp keeps its own log of the last hour (Android's own log
 * is too short). This part saves every Android log line of LinkUp's process
 * (calls, transport, Nearby, boot, crashes...). The app side writes its own
 * files in the same folder; "tap Chats 5 times" merges them into one file.
 *
 * One reader per process (started by the app screen or the Keep running
 * service, whichever comes first). It only reads LinkUp's own lines.
 */
object LinkUpLogFile {
    private const val DIR = "linkup_logs"
    private val started = AtomicBoolean(false)
    private val lock = Any()
    private var writer: BufferedWriter? = null
    private var slot = -1L
    private var lastFlushMs = 0L
    @Volatile private var folder: File? = null
    @Volatile private var lastEpoch: String? = null

    fun dir(context: Context): File = File(context.applicationContext.filesDir, DIR).apply { mkdirs() }

    fun start(context: Context) {
        if (!started.compareAndSet(false, true)) return
        val d = dir(context)
        folder = d
        Thread({ captureLoop(d) }, "linkup-log").apply { isDaemon = true; start() }
    }

    private fun captureLoop(d: File) {
        var runs = 0
        while (runs < 20) {
            runs++
            try {
                val pid = android.os.Process.myPid()
                val p = ProcessBuilder("logcat", "-v", "epoch", "--pid=$pid").redirectErrorStream(true).start()
                // After a restart logcat repeats its buffer: skip what we already saved.
                val since = lastEpoch
                p.inputStream.bufferedReader().use { reader ->
                    while (true) {
                        val line = reader.readLine() ?: break
                        if (LogFilePolicy.skipLine(line)) continue
                        val epoch = LogFilePolicy.epochOf(line)
                        if (epoch != null) {
                            if (since != null && epoch.toDouble() <= since.toDouble()) continue
                            lastEpoch = epoch
                        }
                        write(d, line)
                    }
                }
                try { p.destroy() } catch (_: Throwable) {}
            } catch (_: Throwable) {}
            flush()
            try { Thread.sleep(3_000L) } catch (_: InterruptedException) { return }
        }
    }

    private fun write(d: File, line: String) {
        synchronized(lock) {
            val now = System.currentTimeMillis()
            val s = LogFilePolicy.slotOf(now)
            try {
                if (s != slot || writer == null) {
                    try { writer?.close() } catch (_: Throwable) {}
                    d.mkdirs()
                    writer = BufferedWriter(FileWriter(File(d, LogFilePolicy.nativeFileName(s)), true), 16 * 1024)
                    slot = s
                    prune(d, s)
                }
                writer?.write(line)
                writer?.newLine()
                if (now - lastFlushMs >= 1_000L) { writer?.flush(); lastFlushMs = now }
            } catch (_: Throwable) {
                try { writer?.close() } catch (_: Throwable) {}
                writer = null
            }
        }
    }

    fun flush() {
        synchronized(lock) { try { writer?.flush() } catch (_: Throwable) {} }
    }

    private fun prune(d: File, nowSlot: Long) {
        val files = d.listFiles()?.mapNotNull { f ->
            LogFilePolicy.slotFromName(f.name)?.let { LogFilePolicy.LogFileInfo(f.name, it, f.length()) }
        } ?: return
        for (name in LogFilePolicy.filesToDelete(files, nowSlot)) {
            try { File(d, name).delete() } catch (_: Throwable) {}
        }
    }

    /** Account reset / log out: every log file goes. */
    fun clear(context: Context) {
        synchronized(lock) {
            try { writer?.close() } catch (_: Throwable) {}
            writer = null
            slot = -1L
            dir(context).listFiles()?.forEach { f ->
                if (LogFilePolicy.slotFromName(f.name) != null) try { f.delete() } catch (_: Throwable) {}
            }
        }
    }

    /** For the share step: flushes, then tells the app where things are. */
    fun info(context: Context): Map<String, Any?> {
        flush()
        synchronized(lock) { prune(dir(context), LogFilePolicy.slotOf(System.currentTimeMillis())) }
        val app = context.applicationContext
        val pkg = try { app.packageManager.getPackageInfo(app.packageName, 0) } catch (_: Throwable) { null }
        @Suppress("DEPRECATION")
        val code = if (pkg == null) 0L else if (Build.VERSION.SDK_INT >= 28) pkg.longVersionCode else pkg.versionCode.toLong()
        return mapOf(
            "dir" to dir(app).absolutePath,
            "cache_dir" to app.cacheDir.absolutePath,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "android" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "version_name" to (pkg?.versionName ?: ""),
            "version_code" to code,
            "native_running" to started.get(),
        )
    }
}

/** Bundle 180: same channel for the app screen and the no-screen engine. */
fun registerLogChannel(context: Context, messenger: io.flutter.plugin.common.BinaryMessenger) {
    val app = context.applicationContext
    io.flutter.plugin.common.MethodChannel(messenger, "locallink/logs").setMethodCallHandler { call, result ->
        try {
            when (call.method) {
                "info" -> { LinkUpLogFile.start(app); result.success(LinkUpLogFile.info(app)) }
                "clear" -> { LinkUpLogFile.clear(app); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("LOGS", e.message, null)
        }
    }
}
