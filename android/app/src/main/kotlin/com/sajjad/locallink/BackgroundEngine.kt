package com.sajjad.locallink

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Bundle 169 (4.3): after a reboot the app's own engine starts in the
 * background (no screen) so server messages, nearby messages on Local Wi-Fi,
 * notifications and the outbox work before the user opens LocalLink.
 *
 * It runs the Dart entry point `backgroundMain` with a small set of channels
 * ([BackgroundChannels]). When the user opens the app, MainActivity stops it
 * first, so only one engine ever runs the app at a time.
 */
object BackgroundEngine {
    private const val TAG = "LocalLinkBoot"
    private const val PREFS = "locallink_background_engine"
    private const val KEY_OPENED_VERSION = "opened_version"
    private const val ENTRY_POINT = "backgroundMain"

    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channels: BackgroundChannels? = null
    @Volatile private var idleAt = 0L

    fun isRunning(): Boolean = engine != null

    /** The app was opened on this version (its database is up to date). */
    fun markAppOpened(context: Context) {
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putLong(KEY_OPENED_VERSION, versionCode(context)).apply()
        } catch (_: Exception) {}
    }

    /** Returns null when started, "posted" when moved to the main thread, else the skip reason. */
    fun startAfterBoot(context: Context, bootStartOk: Boolean): String? {
        val app = context.applicationContext
        if (Looper.myLooper() != Looper.getMainLooper()) {
            main.post { startAfterBoot(app, bootStartOk) }
            return "posted"
        }
        val opened = try {
            app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY_OPENED_VERSION, 0L)
        } catch (_: Exception) { 0L }
        val skip = BackgroundEnginePolicy.skipReason(
            bootStartOk = bootStartOk,
            appOpen = MainActivity.isOpen(),
            running = engine != null,
            openedVersion = opened,
            currentVersion = versionCode(app),
        )
        if (skip != null) {
            Log.i(TAG, "BOOT_ENGINE_SKIPPED reason=$skip")
            return skip
        }
        return launch(app, "BOOT_ENGINE_START")
    }

    /**
     * Bundle 175 (3): the screen went away (swipe, Back exit, restart after a
     * kill, a nearby event nobody reads). Same engine, same rules: only one
     * engine runs the app at a time; opening the app stops this one.
     */
    fun startNoScreen(context: Context, reason: String, delayMs: Long = 0L): String? {
        val app = context.applicationContext
        if (delayMs > 0L || Looper.myLooper() != Looper.getMainLooper()) {
            main.postDelayed({ startNoScreen(app, reason) }, delayMs)
            return "posted"
        }
        val opened = try {
            app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY_OPENED_VERSION, 0L)
        } catch (_: Exception) { 0L }
        val skip = BackgroundEnginePolicy.noScreenSkipReason(
            enabled = BackgroundHealth.isEnabled(app),
            serviceRunning = LocalLinkTransportService.isRunning(),
            appOpen = MainActivity.isOpen(),
            running = engine != null,
            openedVersion = opened,
            currentVersion = versionCode(app),
            idleBlocked = android.os.SystemClock.elapsedRealtime() - idleAt < BackgroundEnginePolicy.IDLE_BLOCK_MS && idleAt > 0L,
        )
        if (skip != null) {
            if (skip != "running" && skip != "app_open") Log.i(TAG, "BG_ENGINE_SKIPPED reason=$skip trigger=$reason")
            return skip
        }
        return launch(app, "BG_ENGINE_START reason=$reason")
    }

    private fun launch(app: Context, logLine: String): String? {
        return try {
            val started = FlutterEngine(app)
            val bound = BackgroundChannels(app) { reason -> stop(reason) }
            bound.register(started.dartExecutor.binaryMessenger)
            started.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    ENTRY_POINT,
                ),
            )
            engine = started
            channels = bound
            Log.i(TAG, logLine)
            null
        } catch (t: Throwable) {
            Log.w(TAG, "BOOT_ENGINE_FAILED reason=${t.javaClass.simpleName}")
            channels?.release()
            channels = null
            "error"
        }
    }

    /** Bundle 176 (4): hand a call notification action (Reject) to this engine. */
    fun dispatchCallAction(event: Map<String, Any?>): Boolean = channels?.dispatchCallAction(event) ?: false

    /** Stops the background engine (the app was opened, or Dart had nothing to do). */
    fun stop(reason: String) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            main.post { stop(reason) }
            return
        }
        val running = engine ?: return
        engine = null
        // Bundle 175 (3): Dart had nothing to do - don't restart it for every event.
        idleAt = if (reason.startsWith("idle_")) android.os.SystemClock.elapsedRealtime() else 0L
        channels?.release()
        channels = null
        try { running.destroy() } catch (_: Exception) {}
        Log.i(TAG, "BOOT_ENGINE_STOP reason=$reason")
    }

    @Suppress("DEPRECATION")
    private fun versionCode(context: Context): Long = try {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    } catch (_: Exception) { 0L }
}
