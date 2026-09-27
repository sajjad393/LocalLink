package com.sajjad.locallink

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build

/**
 * Owns only the local incoming-call ringtone and its audio focus.
 * Call signaling/media remains in the existing Flutter/mesh call stack.
 */
object CallRingtoneManager {
    private var player: MediaPlayer? = null
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var wantsRinging = false

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (wantsRinging) {
                    player?.setVolume(1f, 1f)
                    if (player != null && !player!!.isPlaying) player?.start()
                }
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                releasePlayerOnly()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                player?.pause()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                player?.setVolume(0.25f, 0.25f)
            }
        }
    }

    @Synchronized
    fun start(context: Context) {
        wantsRinging = true
        if (player?.isPlaying == true) return

        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager = manager
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusListener)
                .setWillPauseWhenDucked(true)
                .build()
            manager.requestAudioFocus(focusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_RING,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            )
        }

        if (granted != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            wantsRinging = false
            releasePlayerOnly()
            return
        }

        runCatching {
            player = MediaPlayer.create(context.applicationContext, R.raw.locallink_ringtone)?.apply {
                isLooping = true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val attributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    setAudioAttributes(attributes)
                }
                setOnCompletionListener { if (wantsRinging) start() }
                start()
            }
        }.onFailure {
            releasePlayerOnly()
        }
    }

    @Synchronized
    fun stop() {
        wantsRinging = false
        releasePlayerOnly()
        abandonFocus()
    }

    @Synchronized
    fun clear() {
        stop()
    }

    @Synchronized
    private fun releasePlayerOnly() {
        runCatching { player?.stop() }
        runCatching { player?.reset() }
        runCatching { player?.release() }
        player = null
    }

    @Synchronized
    private fun abandonFocus() {
        val manager = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { runCatching { manager.abandonAudioFocusRequest(it) } }
        } else {
            @Suppress("DEPRECATION")
            runCatching { manager.abandonAudioFocus(focusListener) }
        }
        focusRequest = null
        audioManager = null
    }
}
