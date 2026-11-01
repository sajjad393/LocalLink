package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.PriorityQueue
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.sin
import kotlin.random.Random

/**
 * Bundle 184: voice breaking in calls. The waiting line (CallJitterBuffer) is
 * run against simulated networks, next to a copy of the old 179 rules.
 * Simulation only - real proof comes from the phone logs (CALL_VOICE_SUMMARY).
 */
class Voice184Test {

    // ---------------- simulated speech ----------------

    private val talkFrames = 70   // 1.4 s talking
    private val cycleFrames = 100 // then 0.6 s quiet

    private fun talking(k: Int) = k % cycleFrames < talkFrames

    private fun frame(k: Int): ShortArray {
        val out = ShortArray(320)
        val noise = Random(k)
        for (i in 0 until 320) {
            val n = k * 320L + i
            val t = n / 16_000.0
            out[i] = if (talking(k)) {
                val env = 6_000.0 * (0.6 + 0.4 * sin(2 * PI * 3 * t))
                (env * (0.6 * sin(2 * PI * 120 * t) + 0.3 * sin(2 * PI * 240 * t) + 0.1 * sin(2 * PI * 360 * t))).toInt().toShort()
            } else {
                (noise.nextInt(81) - 40).toShort()
            }
        }
        return out
    }

    private val frames = HashMap<Int, ShortArray>()
    private fun pcm(k: Int) = frames.getOrPut(k) { frame(k) }

    // ---------------- simulated networks ----------------
    // arrival time (ms) of the piece sent at 20*k, or null = lost.

    private fun steady(seed: Int = 1): (Int) -> Double? {
        val r = Random(seed)
        val d = DoubleArray(20_000) { 8.0 + r.nextDouble() * 6.0 }
        return { k -> 20.0 * k + d[k] }
    }

    private fun bunches(periodMs: Double, seed: Int = 2): (Int) -> Double? {
        val r = Random(seed)
        val d = DoubleArray(20_000) { r.nextDouble() * 3.0 }
        return { k -> ceil((20.0 * k + 3.0) / periodMs) * periodMs + d[k] }
    }

    /** Wi-Fi naps: random 80-300 ms naps every 150-500 ms, TCP keeps order. */
    private fun wifiNaps(seed: Int = 7, awakeMin: Double = 150.0, awakeSpan: Double = 350.0, napMin: Double = 80.0, napSpan: Double = 220.0): (Int) -> Double? {
        val r = Random(seed)
        val naps = ArrayList<Pair<Double, Double>>()
        var t = 200.0
        while (t < 400_000.0) {
            val awake = awakeMin + r.nextDouble() * awakeSpan
            val nap = napMin + r.nextDouble() * napSpan
            naps.add((t + awake) to (t + awake + nap))
            t += awake + nap
        }
        var idx = 0
        var lastArrival = 0.0
        val memo = HashMap<Int, Double>()
        return { k ->
            memo.getOrPut(k) {
                val send = 20.0 * k + 4.0
                while (idx < naps.size && naps[idx].second < send) idx++
                val inNap = idx < naps.size && send >= naps[idx].first && send < naps[idx].second
                var a = if (inNap) naps[idx].second + 1.0 else send
                if (a < lastArrival) a = lastArrival
                lastArrival = a
                a
            }
        }
    }

    private fun withLoss(base: (Int) -> Double?, percent: Int, seed: Int = 5): (Int) -> Double? {
        val r = Random(seed)
        val lost = BooleanArray(20_000) { r.nextInt(100) < percent }
        return { k -> if (lost[k]) null else base(k) }
    }

    private fun lostSet(percent: Int, seed: Int = 5): BooleanArray {
        val r = Random(seed)
        return BooleanArray(20_000) { r.nextInt(100) < percent }
    }

    private fun freeze(fromMs: Double, toMs: Double): (Int) -> Double? {
        val base = steady(3)
        return { k ->
            val a = base(k)!!
            if (20.0 * k in fromMs..toMs) toMs + 5.0 + (20.0 * k - fromMs) / 1000.0 else a
        }
    }

    // ---------------- the simulator ----------------

    class Result(
        val arrived: Long, val played: Long, val talkPlayed: Double, val cutTalk: Long, val cutQuiet: Long,
        val concealed: Long, val lost: Long, val rebuffers: Long, val meanLineMs: Double, val lateLineMs: Double,
        val underruns: Int, val playedPercent: Int, val target: Int,
    )

    /**
     * 1 ms steps. The speaker eats 16 samples a ms (times [drift]); the speaker
     * thread pulls whenever the 80 ms speaker buffer has room (like a blocking write).
     * [recoverPrev] = UDP redundancy: a lost piece comes with the next one.
     */
    private fun runNew(network: (Int) -> Double?, seconds: Int, drift: Double = 0.0, recoverPrev: BooleanArray? = null): Result {
        val count = seconds * 50
        val arrivals = ArrayList<Pair<Double, Int>>()
        for (k in 0 until count) {
            val a = network(k)
            if (a != null) arrivals.add(a to k)
            else if (recoverPrev != null && k + 1 < count) {
                val next = network(k + 1)
                if (next != null) arrivals.add(next to k)
            }
        }
        arrivals.sortWith(compareBy({ it.first }, { it.second }))
        val jb = CallJitterBuffer()
        var fifo = 0.0
        val capacity = 1_280.0
        var ai = 0
        var lineSum = 0.0; var lineN = 0
        var lateSum = 0.0; var lateN = 0
        var underruns = 0
        var started = false
        val end = count * 20 + 1_500
        for (t in 0 until end) {
            while (ai < arrivals.size && arrivals[ai].first < t + 1) {
                val (at, k) = arrivals[ai++]
                jb.insert(k.toLong(), pcm(k), at.toLong())
            }
            while (fifo <= capacity - 320) {
                val out = jb.pull()
                if (out.kind != CallJitterBuffer.Kind.SILENCE) started = true
                fifo += out.pcm.size
            }
            val eat = 16.0 * (1.0 + drift)
            if (fifo < eat) { if (started && jb.isPlaying) underruns++; fifo = 0.0 } else fifo -= eat
            if (t > 2_000 && t < count * 20) {
                lineSum += jb.storedMs; lineN++
                if (t > count * 20 - 20_000) { lateSum += jb.storedMs; lateN++ }
            }
        }
        val c = jb.counters
        val talk = if (c.arrivedTalking > 0) c.playedTalking * 100.0 / c.arrivedTalking else 100.0
        val pct = CallVoiceHealth.playedPercent(CallVoiceHealth.Snapshot(arrived = c.arrived, played = c.played, cutQuiet = c.cutQuiet))
        return Result(c.arrived, c.played, talk, c.cutTalking, c.cutQuiet, c.concealed, c.lost, c.rebuffers,
            if (lineN > 0) lineSum / lineN else 0.0, if (lateN > 0) lateSum / lateN else 0.0, underruns, pct, jb.target)
    }

    /** A copy of the 179 rules (cut over 120 ms back to 60 ms, 12-piece line). */
    private fun runOld(network: (Int) -> Double?, seconds: Int): Pair<Long, Long> {
        val count = seconds * 50
        val arrivals = ArrayList<Pair<Double, Int>>()
        for (k in 0 until count) network(k)?.let { arrivals.add(it to k) }
        arrivals.sortWith(compareBy({ it.first }, { it.second }))
        val queue = PriorityQueue<Int>()
        var fifo = 0.0
        var ai = 0
        var played = 0L
        for (t in 0 until count * 20 + 1_500) {
            while (ai < arrivals.size && arrivals[ai].first < t + 1) {
                if (queue.size >= 12) queue.poll()
                queue.add(arrivals[ai++].second)
            }
            while (fifo <= 1_280.0 - 320 && queue.isNotEmpty()) {
                if (queue.size > 6) repeat(queue.size - 3) { queue.poll() }
                queue.poll()
                played++
                fifo += 320
            }
            fifo = (fifo - 16.0).coerceAtLeast(0.0)
        }
        return arrivals.size.toLong() to played
    }

    // ---------------- G1: networks ----------------

    @Test fun `steady Wi-Fi plays everything with a short line`() {
        val r = runNew(steady(), 60)
        assertTrue("talk ${r.talkPlayed}", r.talkPlayed >= 99.5)
        assertEquals(0L, r.cutTalk)
        assertTrue("line ${r.meanLineMs}", r.meanLineMs <= 100.0)
        assertTrue("rebuffers ${r.rebuffers}", r.rebuffers <= 1L)
        assertTrue(r.playedPercent >= 99)
    }

    @Test fun `100 ms bunches play everything`() {
        val r = runNew(bunches(102.4), 60)
        assertTrue("talk ${r.talkPlayed}", r.talkPlayed >= 98.0)
        assertEquals(0L, r.cutTalk)
        assertTrue("line ${r.meanLineMs}", r.meanLineMs <= 200.0)
        assertTrue("played ${r.playedPercent}", r.playedPercent >= 97)
    }

    @Test fun `300 ms bunches from screen-off Wi-Fi play everything within 0_3 s`() {
        val r = runNew(bunches(307.2), 60)
        assertTrue("talk ${r.talkPlayed}", r.talkPlayed >= 97.0)
        assertEquals(0L, r.cutTalk)
        assertTrue("line ${r.meanLineMs}", r.meanLineMs <= 300.0)
        assertTrue("played ${r.playedPercent}", r.playedPercent >= 97)
        assertTrue("target ${r.target}", r.target <= CallJitterBuffer.MAX_TARGET_FRAMES)
    }

    @Test fun `random Wi-Fi naps play everything`() {
        val r = runNew(wifiNaps(), 90)
        assertTrue("talk ${r.talkPlayed}", r.talkPlayed >= 97.0)
        assertEquals(0L, r.cutTalk)
        assertTrue("line ${r.meanLineMs}", r.meanLineMs <= 300.0)
        assertTrue("played ${r.playedPercent}", r.playedPercent >= 97)
    }

    @Test fun `5 percent loss is hidden, and the piece carried in the next one brings it back`() {
        val noRed = runNew(withLoss(steady(4), 5), 60)
        assertTrue("lost ${noRed.lost}", noRed.lost > 50)
        assertTrue("hidden ${noRed.concealed} lost ${noRed.lost}", noRed.concealed >= noRed.lost * 9 / 10)
        val red = runNew(withLoss(steady(4), 5), 60, recoverPrev = lostSet(5))
        assertTrue("lost with redundancy ${red.lost}", red.lost * 10 < noRed.lost)
        assertTrue("talk ${red.talkPlayed}", red.talkPlayed >= 99.0)
    }

    @Test fun `a 1 s freeze comes back to a short line`() {
        val r = runNew(freeze(20_000.0, 21_000.0), 60)
        assertTrue("late line ${r.lateLineMs}", r.lateLineMs <= 200.0)
        assertTrue("talk ${r.talkPlayed}", r.talkPlayed >= 90.0)
    }

    @Test fun `speaker clock 0_1 percent off either way stays smooth`() {
        for (drift in listOf(0.001, -0.001)) {
            val r = runNew(steady(9), 120, drift = drift)
            assertTrue("drift $drift talk ${r.talkPlayed}", r.talkPlayed >= 99.0)
            assertEquals(0L, r.cutTalk)
            assertTrue("drift $drift rebuffers ${r.rebuffers}", r.rebuffers <= 2L)
            assertTrue("drift $drift line ${r.meanLineMs}", r.meanLineMs <= 150.0)
        }
    }

    // ---------------- G2: replay of the 2026-11-01 call ----------------

    /** Like the 2026-11-01 call (screen-off Wi-Fi): naps of 150-320 ms with short awake moments. */
    private fun callReplay() = wifiNaps(11, awakeMin = 40.0, awakeSpan = 160.0, napMin = 150.0, napSpan = 170.0)

    @Test fun `old rules lose a big share on napping Wi-Fi, new rules keep it`() {
        val (arrived, played) = runOld(callReplay(), 95)
        val oldPct = played * 100 / arrived
        val r = runNew(callReplay(), 95)
        println("VOICE184_REPLAY old_played=$oldPct% new_played=${r.playedPercent}% talk=${"%.1f".format(r.talkPlayed)}% cut_talk=${r.cutTalk} hidden=${r.concealed} line_ms=${r.meanLineMs.toInt()}")
        assertTrue("old $oldPct", oldPct <= 70)
        assertTrue("new ${r.playedPercent}", r.playedPercent >= 97)
        assertTrue("talk ${r.talkPlayed}", r.talkPlayed >= 97.0)
        assertEquals(0L, r.cutTalk)
        assertTrue("line ${r.meanLineMs}", r.meanLineMs <= 300.0)
    }

    @Test fun `print the simulation table`() {
        val rows = listOf(
            "steady" to steady(), "bunch100" to bunches(102.4), "bunch300" to bunches(307.2), "naps" to wifiNaps(), "replay" to callReplay(),
        )
        for ((name, net) in rows) {
            val (a, p) = runOld(net, 60)
            val r = runNew(net, 60)
            println("VOICE184_SIM $name old=${p * 100 / a}% new=${r.playedPercent}% talk=${"%.1f".format(r.talkPlayed)}% cut_talk=${r.cutTalk} cut_quiet=${r.cutQuiet} hidden=${r.concealed} rebuffer=${r.rebuffers} line_ms=${r.meanLineMs.toInt()} target_ms=${r.target * 20}")
        }
    }

    // ---------------- waiting line details ----------------

    @Test fun `waits for the target before playing, then plays in order`() {
        val jb = CallJitterBuffer()
        jb.insert(0, pcm(0), 0)
        assertEquals(CallJitterBuffer.Kind.SILENCE, jb.pull().kind)
        for (k in 1 until 4) jb.insert(k.toLong(), pcm(k), 20L * k)
        val first = jb.pull()
        assertEquals(CallJitterBuffer.Kind.NORMAL, first.kind)
        assertEquals(320, first.pcm.size)
        assertTrue(abs(first.pcm[0].toInt()) <= 1) // fades in
        assertTrue(jb.isPlaying)
    }

    @Test fun `late and doubled pieces are dropped and counted`() {
        val jb = CallJitterBuffer()
        for (k in 0 until 5) jb.insert(k.toLong(), pcm(k), 20L * k)
        jb.pull(); jb.pull()
        assertTrue(jb.isLate(0))
        assertFalse(jb.insert(0, pcm(0), 200))
        assertFalse(jb.insert(4, pcm(4), 200))
        assertEquals(1L, jb.counters.late)
        assertEquals(1L, jb.counters.duplicate)
    }

    @Test fun `an empty line repeats the last sound softer for at most 60 ms`() {
        val jb = CallJitterBuffer()
        for (k in 0 until 8) jb.insert(k.toLong(), pcm(k), 20L * k)
        repeat(8) { jb.pull() }
        val hidden = (0 until 3).map { jb.pull() }
        hidden.forEach { assertEquals(CallJitterBuffer.Kind.CONCEALED, it.kind) }
        val loud = hidden.map { o -> o.pcm.maxOf { abs(it.toInt()) } }
        assertTrue("first hidden slot has sound $loud", loud[0] > 1_000)
        assertTrue("gets softer $loud", loud[2] < loud[0])
        assertEquals(CallJitterBuffer.Kind.SILENCE, jb.pull().kind)
        assertEquals(1L, jb.counters.rebuffers)
    }

    @Test fun `a lost piece is hidden and counted`() {
        val jb = CallJitterBuffer()
        for (k in 0 until 10) if (k != 6) jb.insert(k.toLong(), pcm(k), 20L * k)
        val kinds = (0 until 9).map { jb.pull().kind }
        assertTrue(kinds.contains(CallJitterBuffer.Kind.CONCEALED))
        assertEquals(1L, jb.counters.lost)
    }

    @Test fun `taking one pitch period out keeps the sound`() {
        val jb = CallJitterBuffer()
        val block = ShortArray(640)
        for (i in block.indices) block[i] = (8_000 * sin(2 * PI * 125 * i / 16_000.0)).toInt().toShort()
        val (lag, corr) = jb.bestLag(block)
        assertEquals(128, lag) // 16000 / 125
        assertTrue(corr > 0.95)
        val out = jb.removePeriod(block, lag)
        assertEquals(640 - 128, out.size)
        for (i in out.indices) assertTrue(abs(out[i] - block[i]) < 300)
    }

    @Test fun `the target grows at once with bunches and shrinks slowly`() {
        val jb = CallJitterBuffer()
        assertEquals(CallJitterBuffer.START_TARGET_FRAMES, jb.target)
        // 300 ms bunches.
        for (k in 0 until 100) {
            jb.insert(k.toLong(), pcm(k), (ceil(20.0 * k / 300.0) * 300).toLong())
            jb.pull()
        }
        val high = jb.target
        assertTrue("high $high", high >= 12)
        assertTrue(high <= CallJitterBuffer.MAX_TARGET_FRAMES)
        // Then steady: one step down per 5 s at most.
        for (k in 100 until 400) {
            jb.insert(k.toLong(), pcm(k), 20L * k + 3_000)
            jb.pull()
        }
        assertTrue("after 6 s ${jb.target} vs $high", jb.target >= high - 2)
    }

    @Test fun `the other phone restarting its numbers starts a new stream`() {
        val jb = CallJitterBuffer()
        for (k in 1_000 until 1_010) jb.insert(k.toLong(), pcm(k % 100), 20L * k)
        repeat(6) { jb.pull() }
        var kept = false
        for (k in 0 until 30) kept = jb.insert(k.toLong(), pcm(k), 30_000L + 20L * k) || kept
        assertTrue(kept)
        assertEquals(1L, jb.counters.resets)
    }

    @Test fun `pcm bytes round trip`() {
        val s = shortArrayOf(0, 1, -1, 32767, -32768, 1234)
        assertTrue(s.contentEquals(CallPcm.toShorts(CallPcm.toBytes(s))))
    }

    // ---------------- UDP ----------------

    @Test fun `a voice datagram round trips and junk is refused`() {
        val bytes = CallVoiceUdp.encode("a1", "b2", "0123456789abcdef", "bm9uY2U=", "Y2lwaGVy")
        val d = CallVoiceUdp.decode(bytes)
        assertNotNull(d)
        assertEquals("a1", d!!.sender)
        assertEquals("b2", d.recipient)
        assertNull(CallVoiceUdp.decode("hello".toByteArray()))
        assertNull(CallVoiceUdp.decode("{\"t\":\"x\"}".toByteArray()))
        assertNull(CallVoiceUdp.decode("{\"t\":\"lv1\",\"s\":\"a\"}".toByteArray()))
    }

    @Test fun `UDP is used only while the friend says it gets it`() {
        val u = CallVoiceUdpState()
        assertFalse(u.useUdp(true, 1_000))
        u.onPeerFlag(true, 1_000)
        assertTrue(u.useUdp(true, 1_500))
        assertFalse(u.useUdp(false, 1_500)) // no address
        assertFalse(u.useUdp(true, 2_100)) // friend stopped saying ur=1 -> TCP
        u.onPeerFlag(false, 2_200)
        assertFalse(u.useUdp(true, 2_300))
    }

    @Test fun `our ur flag follows our own UDP arrivals`() {
        val u = CallVoiceUdpState()
        assertFalse(u.receivingUdp(100))
        u.onUdpReceived("192.168.18.32", 8992, 1_000)
        assertTrue(u.receivingUdp(2_400))
        assertFalse(u.receivingUdp(2_600))
    }

    @Test fun `send target prefers the address the friend's UDP came from`() {
        val u = CallVoiceUdpState()
        assertNull(u.target(null, 0))
        assertEquals("10.0.0.2" to CallVoiceUdp.PORT, u.target("10.0.0.2", 0))
        u.onUdpReceived("10.0.0.9", 40_000, 1_000)
        assertEquals("10.0.0.9" to 40_000, u.target("10.0.0.2", 2_000))
        assertEquals("10.0.0.2" to CallVoiceUdp.PORT, u.target("10.0.0.2", 5_000))
    }

    @Test fun `a replayed old datagram moves nothing`() {
        val u = CallVoiceUdpState()
        assertTrue(u.onUdpMedia("10.0.0.2", 8992, 100, 1_000))
        assertFalse(u.onUdpMedia("10.0.0.66", 8992, 50, 1_100)) // old piece from elsewhere
        assertEquals("10.0.0.2" to 8992, u.target(null, 1_200))
        assertTrue(u.onUdpProbe("10.0.0.2", 8992, 5_000, 1_300))
        assertFalse(u.onUdpProbe("10.0.0.66", 8992, 5_000, 1_400))
        assertEquals("10.0.0.2" to 8992, u.target(null, 1_500))
    }

    @Test fun `probes go every half second`() {
        val u = CallVoiceUdpState()
        assertTrue(u.probeDue(1_000))
        assertFalse(u.probeDue(1_200))
        assertTrue(u.probeDue(1_500))
    }

    // ---------------- Nearby pause ----------------

    @Test fun `Nearby search pauses during a call and comes back 2 s after`() {
        CallNearbyPause.resetForTest()
        assertTrue(CallNearbyPause.searchAllowed(1_000))
        CallNearbyPause.callStarted()
        assertFalse(CallNearbyPause.searchAllowed(2_000))
        CallNearbyPause.callEnded(10_000)
        assertFalse(CallNearbyPause.searchAllowed(11_000))
        assertTrue(CallNearbyPause.searchAllowed(12_000))
        CallNearbyPause.resetForTest()
    }

    // ---------------- health line ----------------

    @Test fun `health line says played percent and warns under 95`() {
        val good = CallVoiceHealth.Snapshot(arrived = 500, played = 495, cutQuiet = 3)
        assertEquals(99, CallVoiceHealth.playedPercent(good))
        assertFalse(CallVoiceHealth.warn(good))
        val bad = CallVoiceHealth.Snapshot(arrived = 500, played = 250)
        assertTrue(CallVoiceHealth.warn(bad))
        val line = CallVoiceHealth.line("CALL_VOICE_HEALTH", "c1", good, CallVoiceHealth.Now(link = "lan", screenOn = false, output = "ear", udp = true))
        assertTrue(line, line.startsWith("CALL_VOICE_HEALTH call=c1 played=99% arrived=500 cut_talk=0"))
        assertTrue(line, line.contains(" udp=1 ") && line.contains(" link=lan screen=off out=ear "))
        val diff = good - CallVoiceHealth.Snapshot(arrived = 100, played = 99)
        assertEquals(400L, diff.arrived)
    }

    // ---------------- G3: wiring in the service ----------------

    private fun source(name: String): String {
        val candidates = listOf("main/kotlin/com/sajjad/locallink/$name", "src/main/kotlin/com/sajjad/locallink/$name", "app/src/main/kotlin/com/sajjad/locallink/$name", "android/app/src/main/kotlin/com/sajjad/locallink/$name")
        val f = candidates.map { File(it) }.firstOrNull { it.exists() } ?: return ""
        return f.readText()
    }

    @Test fun `no app event per voice piece and voice runs at audio priority`() {
        val s = source("LocalLinkTransportService.kt")
        if (s.isEmpty()) return
        assertFalse(s.contains("transportEvent(\"call_media_received\""))
        assertTrue(s.contains("if (packet.type == \"call_media\" || packet.type == MeshRelayPolicy.SEALED_VOICE) return"))
        assertTrue(s.contains("THREAD_PRIORITY_URGENT_AUDIO"))
        assertTrue(s.contains("CallJitterBuffer()"))
        assertTrue(s.contains("CallNearbyPause.callStarted()"))
        assertTrue(s.contains("CallNearbyPause.callEnded()"))
        assertFalse(s.contains("rxFramesToSkip"))
    }

    @Test fun `both Nearby searches check the call pause`() {
        val radio = source("NearbyRadio.kt")
        val tags = source("NearbyTagManager.kt")
        if (radio.isEmpty() || tags.isEmpty()) return
        assertTrue(radio.contains("CallNearbyPause.searchAllowed()"))
        assertTrue(tags.contains("CallNearbyPause.searchAllowed()"))
    }
}
