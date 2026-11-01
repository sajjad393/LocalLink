package com.sajjad.locallink

/** Bundle 186 (C1/C2): the app-wide call audio thread (see [CallAudioQueue]). */
object CallAudioThread {
    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    private val queue: CallAudioQueue by lazy {
        CallAudioQueue(reply = { main.post(it) }, log = { android.util.Log.i("LocalLinkCall", it) })
    }

    /** [block] on the call audio thread; [done] on the main thread (error or null). */
    fun run(name: String, block: () -> Unit, done: (Throwable?) -> Unit) = queue.run(name, block, done)
}
