package com.sajjad.locallink

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import androidx.lifecycle.Lifecycle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bundle 147: chat video picture-in-picture (floating window over other apps).
 *
 * Dart (ChatVideoHub) says when a chat video is playing via
 * `locallink/pip` setReady(ready, w, h, playing). Only then does leaving the
 * app float the video. Dart never sets ready during a call, so call screens
 * are never put into PiP.
 *
 * Events on `locallink/pip_events`:
 *  {type: pip, active: true|false, dismissed: bool}
 *  {type: action, action: play|pause|back10|fwd10}  (PiP window buttons)
 */
class ChatVideoPip(private val activity: Activity) {
    companion object {
        private const val ACTION = "com.sajjad.locallink.CHAT_VIDEO_PIP_ACTION"
        private const val EXTRA = "action"
    }

    private var ready = false
    private var ratioW = 16
    private var ratioH = 9
    private var playing = false
    private var sink: EventChannel.EventSink? = null
    private var receiverRegistered = false
    private val main = Handler(Looper.getMainLooper())

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.getStringExtra(EXTRA) ?: return
            sink?.success(mapOf("type" to "action", "action" to action))
        }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "locallink/pip").setMethodCallHandler { call, result ->
            when (call.method) {
                "setReady" -> {
                    ready = call.argument<Boolean>("ready") == true
                    ratioW = (call.argument<Int>("w") ?: 16).coerceAtLeast(1)
                    ratioH = (call.argument<Int>("h") ?: 9).coerceAtLeast(1)
                    playing = call.argument<Boolean>("playing") == true
                    applyParams()
                    result.success(null)
                }
                "isSupported" -> result.success(supported())
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "locallink/pip_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        registerReceiver()
    }

    fun supported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    /** Android 8–11: Home pressed while a chat video plays → float it. */
    fun onUserLeaveHint() {
        if (!ready || !supported()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return // auto-enter does it
        try {
            activity.enterPictureInPictureMode(buildParams())
        } catch (_: Exception) {
        }
    }

    /**
     * Leaving PiP: expanded back to the app (activity started) or the window
     * was swiped away / closed (activity stopped) — the latter stops video.
     */
    fun onModeChanged(active: Boolean, lifecycle: Lifecycle) {
        if (active) {
            sink?.success(mapOf("type" to "pip", "active" to true, "dismissed" to false))
            return
        }
        main.postDelayed({
            val started = lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
            sink?.success(mapOf("type" to "pip", "active" to false, "dismissed" to !started))
        }, 300)
    }

    fun dispose() {
        main.removeCallbacksAndMessages(null)
        if (receiverRegistered) {
            try {
                activity.unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            receiverRegistered = false
        }
        sink = null
    }

    private fun registerReceiver() {
        if (receiverRegistered || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val filter = IntentFilter(ACTION)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                activity.registerReceiver(receiver, filter)
            }
            receiverRegistered = true
        } catch (_: Exception) {
        }
    }

    private fun applyParams() {
        if (!supported()) return
        try {
            activity.setPictureInPictureParams(buildParams())
        } catch (_: Exception) {
        }
    }

    private fun buildParams(): PictureInPictureParams {
        // Android only accepts 1:2.39 .. 2.39:1.
        val r = ratioW.toFloat() / ratioH.toFloat()
        val ratio = when {
            r > 2.39f -> Rational(239, 100)
            r < 1f / 2.39f -> Rational(100, 239)
            else -> Rational(ratioW, ratioH)
        }
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(ratio)
            .setActions(actions())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(ready)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun actions(): List<RemoteAction> = listOf(
        action("back10", android.R.drawable.ic_media_rew, "Back 10 seconds", 1),
        if (playing) action("pause", android.R.drawable.ic_media_pause, "Pause", 2)
        else action("play", android.R.drawable.ic_media_play, "Play", 3),
        action("fwd10", android.R.drawable.ic_media_ff, "Forward 10 seconds", 4),
    )

    private fun action(name: String, icon: Int, title: String, code: Int): RemoteAction {
        val intent = Intent(ACTION).setPackage(activity.packageName).putExtra(EXTRA, name)
        val pending = PendingIntent.getBroadcast(
            activity, 7300 + code, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return RemoteAction(Icon.createWithResource(activity, icon), title, title, pending)
    }
}
