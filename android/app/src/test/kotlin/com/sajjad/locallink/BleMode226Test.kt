package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 226 (B3): scan / advertise modes and the state word. */
class BleMode226Test {
    @Test
    fun `scan modes per state, live call = no scan`() {
        assertEquals("off", NearbyBlePolicy.scanMode(inCall = true, urgent = true, foreground = true))
        assertEquals("low_latency", NearbyBlePolicy.scanMode(inCall = false, urgent = true, foreground = false))
        assertEquals("balanced", NearbyBlePolicy.scanMode(inCall = false, urgent = false, foreground = true))
        assertEquals("low_power", NearbyBlePolicy.scanMode(inCall = false, urgent = false, foreground = false))
    }

    @Test
    fun `advertise modes`() {
        assertEquals("low_latency", NearbyBlePolicy.advMode(urgent = true, inCall = false))
        assertEquals("low_power", NearbyBlePolicy.advMode(urgent = true, inCall = true))
        assertEquals("low_power", NearbyBlePolicy.advMode(urgent = false, inCall = false))
    }

    @Test
    fun `urgent lasts at most 60 s`() {
        assertFalse(NearbyBlePolicy.urgentNow(0L, 5L))
        assertTrue(NearbyBlePolicy.urgentNow(1_000L, 60_999L))
        assertFalse(NearbyBlePolicy.urgentNow(1_000L, 61_000L))
    }

    @Test
    fun `state word`() {
        fun w(sdk: Int = 34, ble: Boolean = true, on: Boolean = true, scan: Boolean = true, adv: Boolean = true, can: Boolean = true) =
            NearbyBlePolicy.stateWord(sdk, ble, on, scan, adv, can)
        assertEquals("on", w())
        assertEquals("unsupported", w(sdk = 28))
        assertEquals("unsupported", w(ble = false))
        assertEquals("no_permission", w(scan = false, on = false))
        assertEquals("off", w(on = false))
        assertEquals("scan_only", w(adv = false))
        assertEquals("scan_only", w(can = false))
    }

    @Test
    fun `closed app may set the Bluetooth wants, never ask the pop-up`() {
        assertTrue(NearbyBackgroundPolicy.isAllowed("setBleWanted"))
        assertTrue(NearbyBackgroundPolicy.isAllowed("bleStatus"))
        assertFalse(NearbyBackgroundPolicy.isAllowed("askBlePermission"))
        assertFalse(NearbyBackgroundPolicy.isAllowed("openBluetoothSettings"))
    }

    @Test
    fun `manifest - scan never for location, no connect, BLE optional`() {
        val m = File("main/AndroidManifest.xml").readText()
        assertTrue(m.contains("android.permission.BLUETOOTH_SCAN\" android:usesPermissionFlags=\"neverForLocation\""))
        assertTrue(m.contains("android.permission.BLUETOOTH_ADVERTISE"))
        assertTrue(m.contains("android.permission.BLUETOOTH\" android:maxSdkVersion=\"30\""))
        assertTrue(m.contains("android.permission.BLUETOOTH_ADMIN\" android:maxSdkVersion=\"30\""))
        assertTrue(m.contains("android.hardware.bluetooth_le\" android:required=\"false\""))
        assertFalse(m.contains("BLUETOOTH_CONNECT"))
    }

    @Test
    fun `the scan always has a filter and stops for call voice`() {
        val src = File("main/kotlin/com/sajjad/locallink/NearbyBle.kt").readText()
        assertTrue(src.contains("scanner.startScan(listOf(filter), settings, scanCallback)"))
        val radio = File("main/kotlin/com/sajjad/locallink/NearbyRadio.kt").readText()
        assertTrue(radio.contains("NearbyBle.onCallVoice(true)"))
        assertTrue(radio.contains("NearbyBle.onCallVoice(false)"))
        assertTrue(radio.contains("NearbyBle.start(a)"))
        assertTrue(radio.contains("NearbyBle.stop(reason)"))
    }
}
