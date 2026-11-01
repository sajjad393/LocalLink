package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 185: ZTE - why it stopped, freezes, ZTE settings, self-test memory. */
class App185Test {
    private val main = File("main/kotlin/com/sajjad/locallink")

    // ---------------------------------------------------------------- A1
    @Test fun `exit reasons have plain names`() {
        assertEquals("low_memory", AppHealthPolicy.reasonName(3))
        assertEquals("force_stop", AppHealthPolicy.reasonName(10))
        assertEquals("permission_change", AppHealthPolicy.reasonName(8))
        assertEquals("crash", AppHealthPolicy.reasonName(4))
        assertEquals("not_responding", AppHealthPolicy.reasonName(6))
        assertEquals("other", AppHealthPolicy.reasonName(13))
        assertEquals("unknown", AppHealthPolicy.reasonName(99))
    }

    @Test fun `importance says if Keep running was on`() {
        assertEquals("open", AppHealthPolicy.importanceName(100))
        assertEquals("service", AppHealthPolicy.importanceName(125))
        assertEquals("visible", AppHealthPolicy.importanceName(200))
        assertEquals("cached", AppHealthPolicy.importanceName(400))
        assertEquals("gone", AppHealthPolicy.importanceName(1000))
    }

    @Test fun `exit line is one clean line`() {
        val line = AppHealthPolicy.exitLine(10, 125, 1_000_000L, 1_065_000L, 150_000L, 210_000L,
            "stop com.sajjad.linkup\nby superkiller")
        assertEquals("APP_LAST_EXIT reason=force_stop code=10 was=service ago_s=65 mem_mb=146 rss_mb=205 " +
            "text=stop com.sajjad.linkup by superkiller", line)
        assertFalse(line.contains('\n'))
        assertTrue(AppHealthPolicy.exitLine(3, 400, 0, 0, 0, 0, null).endsWith("text=-"))
        val long = AppHealthPolicy.exitLine(13, 400, 0, 0, 0, 0, "x".repeat(500))
        assertEquals(120, long.substringAfter("text=").length)
    }

    @Test fun `only new deaths are logged, oldest first, max 3`() {
        assertEquals(listOf(30L, 40L, 50L), AppHealthPolicy.newExits(listOf(50L, 10L, 40L, 30L, 20L), 0L))
        assertEquals(listOf(40L, 50L), AppHealthPolicy.newExits(listOf(50L, 10L, 40L, 30L), 30L))
        assertEquals(emptyList<Long>(), AppHealthPolicy.newExits(listOf(10L, 20L), 20L))
    }

    // ---------------------------------------------------------------- A2
    @Test fun `keep alive line`() {
        assertEquals("KEEP_ALIVE_STATE when=background battery=optimized bg_restricted=n bucket=rare " +
            "notifications=y service=y brand=zte",
            AppHealthPolicy.keepAliveLine("background", false, false, 40, true, true, "ZTE"))
        assertEquals("KEEP_ALIVE_STATE when=open battery=- bg_restricted=- bucket=- notifications=- service=n brand=-",
            AppHealthPolicy.keepAliveLine("open", null, null, null, null, false, ""))
    }

    // ---------------------------------------------------------------- B1
    @Test fun `memory trim frees caches only when it helps`() {
        assertEquals("ui_hidden", AppHealthPolicy.trimName(20))
        assertEquals("background", AppHealthPolicy.trimName(40))
        assertEquals("complete", AppHealthPolicy.trimName(80))
        assertEquals("running_critical", AppHealthPolicy.trimName(15))
        assertFalse(AppHealthPolicy.shouldFreeCaches(20)) // just hidden: keep
        assertFalse(AppHealthPolicy.shouldFreeCaches(5))
        assertTrue(AppHealthPolicy.shouldFreeCaches(40))
        assertTrue(AppHealthPolicy.shouldFreeCaches(80))
        assertTrue(AppHealthPolicy.shouldFreeCaches(15))
    }

    // ---------------------------------------------------------------- A3
    @Test fun `freeze watcher watches 2 minutes after open and during calls`() {
        assertTrue(StallRules.watching(10_000, 5_000, false))
        assertTrue(StallRules.watching(124_999, 5_000, false))
        assertFalse(StallRules.watching(125_000, 5_000, false))
        assertTrue(StallRules.watching(999_999, 5_000, true))
        assertFalse(StallRules.watching(10_000, 0, false)) // never opened (no screen engine)
    }

    @Test fun `freeze lines need 700 ms and 5 s between them`() {
        assertFalse(StallRules.shouldLog(699, 10_000, 0))
        assertTrue(StallRules.shouldLog(700, 10_000, 0))
        assertFalse(StallRules.shouldLog(2_000, 14_999, 10_000))
        assertTrue(StallRules.shouldLog(2_000, 15_000, 10_000))
    }

    @Test fun `freeze place is short`() {
        assertEquals("dart_or_engine", StallRules.describe(listOf(
            "android.os.MessageQueue.nativePollOnce(Native Method)", "android.os.MessageQueue.next(MessageQueue.java:335)")))
        assertEquals("SharedPreferencesImpl.awaitLoadedLocked:300<MainActivity.onCreate:120",
            StallRules.describe(listOf(
                "android.app.SharedPreferencesImpl.awaitLoadedLocked(SharedPreferencesImpl.java:300)",
                "com.sajjad.locallink.MainActivity.onCreate(MainActivity.kt:120)")))
        assertEquals("-", StallRules.describe(emptyList()))
        assertEquals(5, StallRules.describe(List(9) { "a.B.c$it(B.kt:$it)" }).split('<').size)
    }

    // ---------------------------------------------------------------- B2
    @Test fun `ZTE opens its power manager when the old page is missing`() {
        assertEquals(listOf("com.zte.powersavemode", "com.zte.heartyservice"), VendorBackgroundIntents.launchPackages("ZTE"))
        assertTrue(VendorBackgroundIntents.launchPackages("samsung").isEmpty())
        assertTrue(VendorBackgroundIntents.candidates("zte").isNotEmpty())
        val manifest = File("main/AndroidManifest.xml").readText()
        assertTrue(manifest.contains("<package android:name=\"com.zte.powersavemode\" />"))
        val activity = File(main, "MainActivity.kt").readText()
        assertTrue(activity.contains("VendorBackgroundIntents.launchPackages(brand)"))
    }

    // ---------------------------------------------------------------- D1
    @Test fun `self-test answer is reused only for the same builds`() {
        val key = "zte/Z2453/14|87"
        assertEquals(true, OpusSelfTestMemory.savedResult(OpusSelfTestMemory.savedValue(true, key), key))
        assertEquals(false, OpusSelfTestMemory.savedResult(OpusSelfTestMemory.savedValue(false, key), key))
        assertNull(OpusSelfTestMemory.savedResult(OpusSelfTestMemory.savedValue(true, key), "zte/Z2453/14|88"))
        assertNull(OpusSelfTestMemory.savedResult(null, key))
        assertNull(OpusSelfTestMemory.savedResult("maybe|$key", key))
    }

    @Test fun `self-test no longer runs during the start`() {
        val activity = File(main, "MainActivity.kt").readText()
        assertTrue(activity.contains("CallOpusCodec.selfTestLater(this)"))
        assertFalse(activity.contains("Thread { CallOpusCodec.usable() }"))
        val codec = File(main, "CallOpusCodec.kt").readText()
        assertTrue(codec.contains("SELF_TEST_DELAY_MS = 20_000L"))
    }

    // ---------------------------------------------------------------- wiring
    @Test fun `health lines are wired`() {
        val activity = File(main, "MainActivity.kt").readText()
        assertTrue(activity.contains("AppHealth.logExitsOnce(this)"))
        assertTrue(activity.contains("AppHealth.logKeepAlive(this, \"open\")"))
        assertTrue(activity.contains("AppHealth.logKeepAlive(this, \"background\")"))
        assertTrue(activity.contains("AppHealth.onTrim(level)"))
        assertTrue(activity.contains("AppHealth.appOpened()"))
        assertTrue(activity.contains("Thread({ BackgroundHealth.schedule(appCtx) }"))
        val service = File(main, "LocalLinkTransportService.kt").readText()
        assertTrue(service.contains("AppHealth.logExitsOnce(this)"))
        assertTrue(service.contains("CallNearbyPause.callStarted(); AppHealth.startWatcher()"))
    }

    @Test fun `call pause tells the watcher about calls`() {
        CallNearbyPause.resetForTest()
        assertFalse(CallNearbyPause.inCall())
        CallNearbyPause.callStarted()
        assertTrue(CallNearbyPause.inCall())
        CallNearbyPause.callEnded(1_000)
        assertFalse(CallNearbyPause.inCall())
        CallNearbyPause.resetForTest()
    }
}
