package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Bundle 186: answering a call is faster (call audio thread, timing lines). */
class Answer186Test {
    private val main = File("main/kotlin/com/sajjad/locallink")
    private fun src(name: String) = File(main, name).readText()

    // ---------------------------------------------------------------- C1/C2
    @Test fun `call audio jobs run one at a time in order`() {
        val order = Collections.synchronizedList(ArrayList<String>())
        val done = CountDownLatch(3)
        val q = CallAudioQueue(reply = { it.run() })
        q.run("speaker_on", { Thread.sleep(40); order.add("speaker_on") }) { done.countDown() }
        q.run("media_start", { order.add("media_start") }) { done.countDown() }
        q.run("speaker_off", { order.add("speaker_off") }) { done.countDown() }
        assertTrue(done.await(3, TimeUnit.SECONDS))
        assertEquals(listOf("speaker_on", "media_start", "speaker_off"), order)
    }

    @Test fun `jobs run off the calling thread on the call audio thread`() {
        val latch = CountDownLatch(1)
        var name = ""
        CallAudioQueue(reply = { it.run() }).run("x", { name = Thread.currentThread().name }) { latch.countDown() }
        assertTrue(latch.await(3, TimeUnit.SECONDS))
        assertEquals(CallAudioQueue.THREAD_NAME, name)
    }

    @Test fun `an error is handed back and the next job still runs`() {
        val errors = Collections.synchronizedList(ArrayList<Throwable?>())
        val latch = CountDownLatch(2)
        val q = CallAudioQueue(reply = { it.run() })
        q.run("bad", { throw IllegalStateException("AudioRecord initialization failed") }) { errors.add(it); latch.countDown() }
        q.run("good", { }) { errors.add(it); latch.countDown() }
        assertTrue(latch.await(3, TimeUnit.SECONDS))
        assertNotNull(errors[0]); assertEquals("AudioRecord initialization failed", errors[0]!!.message)
        assertNull(errors[1])
    }

    @Test fun `each job writes one timing line`() {
        val lines = Collections.synchronizedList(ArrayList<String>())
        var t = 1000L
        val latch = CountDownLatch(1)
        val q = CallAudioQueue(reply = { it.run() }, clock = { t }, log = { lines.add(it) })
        q.run("route speaker=false", { t += 640 }) { latch.countDown() }
        assertTrue(latch.await(3, TimeUnit.SECONDS))
        assertEquals("CALL_AUDIO_STEP name=route speaker=false ms=640 waited_ms=0 ok=true", lines.single())
        assertEquals("CALL_AUDIO_STEP name=media_start ms=12 waited_ms=3 ok=false", CallAudioQueue.line("media_start", 12, 3, false))
    }

    // ---------------------------------------------------------------- A2
    @Test fun `step timer line names the slowest part`() {
        var t = 0L
        val timer = CallStepTimer { t }
        t = 5; timer.mark("session")
        t = 25; timer.mark("locks")
        t = 300; timer.mark("mic")
        t = 330; timer.mark("go")
        assertEquals(330L, timer.totalMs())
        assertEquals("CALL_MEDIA_START_MS call=c1 total=330 slowest=mic steps=session:5,locks:20,mic:275,go:30",
            timer.line("CALL_MEDIA_START_MS", "call=c1"))
        assertEquals("X total=0 slowest=- steps=", CallStepTimer { 0L }.line("X"))
    }

    // ---------------------------------------------------------------- wiring
    @Test fun `slow audio work is sent to the call audio thread`() {
        val activity = src("MainActivity.kt")
        assertTrue(activity.contains("CallAudioThread.run(\"route speaker=\$enabled\", { applyCallRoute(audioManager, enabled) })"))
        assertTrue(activity.contains("CallAudioThread.run(\"media_start\""))
        assertTrue(activity.contains("CallAudioThread.run(\"media_stop\""))
        assertTrue(activity.contains("CallAudioThread.run(\"route clear\""))
        assertTrue(activity.contains("private fun applyCallRoute("))
        // The mic permission popup still needs the main thread: checked before the queue.
        val start = activity.indexOf("CallAudioThread.run(\"media_start\"")
        val perm = activity.lastIndexOf("checkSelfPermission(Manifest.permission.RECORD_AUDIO)", start)
        assertTrue(perm in 0 until start)
        assertTrue(!activity.contains("setSpeakerphoneOnOld186"))
    }

    @Test fun `service start and stop take turns and log their timing`() {
        val s = src("LocalLinkTransportService.kt")
        assertTrue(s.contains("private val callMediaControlLock = Any()"))
        assertTrue(s.contains("synchronized(callMediaControlLock) {\n        startCallMediaLocked("))
        assertTrue(s.contains("synchronized(callMediaControlLock) {\n        stopCallMediaLocked("))
        assertTrue(s.contains("timer.line(\"CALL_MEDIA_START_MS\""))
        assertTrue(s.contains("CALL_FIRST_VOICE call="))
        assertTrue(s.contains("session.start(timer)"))
        assertTrue(s.contains("throw IllegalStateException(\"transport service is not running\")"))
        val thread = src("CallAudioThread.kt")
        assertTrue(thread.contains("android.os.Looper.getMainLooper()"))
    }
}
