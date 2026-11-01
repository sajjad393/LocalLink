package com.sajjad.locallink

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ThreadFactory

/**
 * Bundle 186 (C1/C2): one "call audio" thread for the slow call-audio work
 * (audio mode, earpiece/speaker choice, mic + speaker start and stop).
 *
 * Before 186 all of it ran on the main thread. Since Flutter 3.32 that is
 * also the Dart + screen thread, so the app froze for ~1.3 s right after
 * Accept on the Realme (Unisoc audio). The jobs run one at a time in the
 * order they came in, so speaker on/off and start/stop never mix up.
 *
 * Pure JVM (no Android classes) so it can be tested; [reply] hands the
 * answer back to the main thread on the phone.
 */
class CallAudioQueue(
    private val reply: (Runnable) -> Unit,
    private val clock: () -> Long = { System.nanoTime() / 1_000_000L },
    private val log: (String) -> Unit = {},
    executor: ExecutorService? = null,
) {
    private val executor: ExecutorService = executor ?: Executors.newSingleThreadExecutor(ThreadFactory { r ->
        Thread(r, THREAD_NAME).apply { isDaemon = true }
    })

    /** Runs [block] on the call audio thread, then [done] (error or null) via [reply]. */
    fun run(name: String, block: () -> Unit, done: (Throwable?) -> Unit) {
        val queuedAt = clock()
        try {
            executor.execute {
                val startedAt = clock()
                var error: Throwable? = null
                try { block() } catch (t: Throwable) { error = t }
                val ms = clock() - startedAt
                log(line(name, ms, startedAt - queuedAt, error == null))
                reply(Runnable { done(error) })
            }
        } catch (t: Throwable) {
            // Queue shut down (should not happen): never leave Dart waiting.
            reply(Runnable { done(t) })
        }
    }

    companion object {
        const val THREAD_NAME = "linkup-call-audio"

        fun line(name: String, ms: Long, waitedMs: Long, ok: Boolean): String =
            "CALL_AUDIO_STEP name=$name ms=$ms waited_ms=$waitedMs ok=$ok"
    }
}

/**
 * Bundle 186 (A2): time for each part of a native call start, for one line
 * `CALL_MEDIA_START_MS total=… slowest=… steps=a:12,b:30`.
 */
class CallStepTimer(private val clock: () -> Long = { System.nanoTime() / 1_000_000L }) {
    private val start = clock()
    private var last = start
    private val steps = ArrayList<Pair<String, Long>>()

    fun mark(name: String) {
        val now = clock()
        steps.add(name to (now - last))
        last = now
    }

    fun totalMs(): Long = last - start

    fun line(event: String, prefix: String = ""): String {
        val slowest = steps.maxByOrNull { it.second }?.first ?: "-"
        val head = if (prefix.isBlank()) "" else "$prefix "
        return "$event ${head}total=${totalMs()} slowest=$slowest steps=" +
            steps.joinToString(",") { "${it.first}:${it.second}" }
    }
}
