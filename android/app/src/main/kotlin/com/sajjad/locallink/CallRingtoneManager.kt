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

    // Dialer-side ringback ("calling…" tone): short, quiet, no audio focus,
    // routed through the voice-call signalling channel like a real ringback.
    private var ringbackPlayer: MediaPlayer? = null

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
            // Bundle 141: attributes must be set BEFORE prepare(); the old
            // MediaPlayer.create() path returned a prepared player, Android
            // rejected the attributes ("state 8") and the tone played at media volume.
            player = preparedPlayer(
                context,
                R.raw.locallink_ringtone,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )?.apply {
                isLooping = true
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
        releaseRingbackOnly()
    }

    @Synchronized
    fun startRingback(context: Context) {
        if (ringbackPlayer?.isPlaying == true) return
        runCatching {
            ringbackPlayer = preparedPlayer(
                context,
                R.raw.locallink_ringback,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )?.apply {
                isLooping = true
                setVolume(0.75f, 0.75f)
                start()
            }
        }.onFailure { releaseRingbackOnly() }
    }

    // Bundle 141: idle -> setAudioAttributes -> setDataSource -> prepare.
    private fun preparedPlayer(context: Context, rawRes: Int, attributes: AudioAttributes): MediaPlayer? {
        val player = MediaPlayer()
        return try {
            player.setAudioAttributes(attributes)
            context.applicationContext.resources.openRawResourceFd(rawRes).use { afd ->
                player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            }
            player.prepare()
            player
        } catch (_: Exception) {
            runCatching { player.release() }
            null
        }
    }

    @Synchronized
    fun stopRingback() {
        releaseRingbackOnly()
    }

    @Synchronized
    private fun releaseRingbackOnly() {
        runCatching { ringbackPlayer?.stop() }
        runCatching { ringbackPlayer?.reset() }
        runCatching { ringbackPlayer?.release() }
        ringbackPlayer = null
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
