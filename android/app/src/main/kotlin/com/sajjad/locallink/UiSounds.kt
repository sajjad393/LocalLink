package com.sajjad.locallink

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool

/**
 * Bundle 198: short in-app sounds (send tick, in-chat pop, voice note
 * tik / swoosh / tok). Our own files in res/raw. Never plays on Silent /
 * Vibrate or during a call. Errors are swallowed (returns false).
 */
object UiSounds {
    /** Pure rule, unit-tested: only in Normal ringer mode and not in a call. */
    fun shouldPlay(ringerMode: Int, audioMode: Int): Boolean {
        if (ringerMode != AudioManager.RINGER_MODE_NORMAL) return false
        if (audioMode == AudioManager.MODE_IN_CALL ||
            audioMode == AudioManager.MODE_IN_COMMUNICATION ||
            audioMode == AudioManager.MODE_RINGTONE) return false
        return true
    }

    /** Pure map from the Dart name to the raw file, unit-tested. */
    fun resFor(name: String): Int? = when (name) {
        "message_sent" -> R.raw.message_sent
        "message_received" -> R.raw.message_received
        "voice_start" -> R.raw.voice_start
        "voice_send" -> R.raw.voice_send
        "voice_cancel" -> R.raw.voice_cancel
        else -> null
    }

    private var pool: SoundPool? = null
    private val loaded = HashMap<Int, Int>() // res -> sound id
    private val ready = HashSet<Int>() // ready sound ids
    private val waiting = HashSet<Int>() // sound ids to play once loaded

    @Synchronized
    fun play(context: Context, name: String): Boolean {
        return try {
            val res = resFor(name) ?: return false
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                ?: return false
            if (!shouldPlay(audio.ringerMode, audio.mode)) return true
            val p = pool ?: SoundPool.Builder()
                .setMaxStreams(2)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .build()
                .also { created ->
                    created.setOnLoadCompleteListener { sp, id, status ->
                        synchronized(this) {
                            if (status == 0) {
                                ready.add(id)
                                if (waiting.remove(id)) sp.play(id, 1f, 1f, 1, 0, 1f)
                            } else {
                                waiting.remove(id)
                            }
                        }
                    }
                    pool = created
                }
            val id = loaded[res] ?: p.load(context.applicationContext, res, 1).also { loaded[res] = it }
            if (id == 0) return false
            if (ready.contains(id)) {
                p.play(id, 1f, 1f, 1, 0, 1f) != 0
            } else {
                waiting.add(id)
                true
            }
        } catch (_: Exception) {
            false
        }
    }
}
