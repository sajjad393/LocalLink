package com.sajjad.locallink

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import android.util.Log
import java.util.UUID

/**
 * Bundle 226 (B3): Bluetooth LE finds LinkUp friends; Wi-Fi still carries
 * everything. Lives with [NearbyRadio] (application context, kept alive by
 * the `connectedDevice` foreground service), so it also works with the app
 * closed. Started by [NearbyRadio.ensure], stopped only by Log out.
 *
 * - Advertises the 10-byte packet from [NearbyBlePolicy] (legacy, not
 *   connectable, no name, no TX power).
 * - Scans ALWAYS with a ScanFilter on LinkUp's service data (needed for
 *   screen-off scanning). Live call = no scan (one antenna on budget phones).
 * - Never turns Bluetooth on, never pairs, never connects (no
 *   Bluetooth connect permission).
 * - Never throws; everything runs on the main looper.
 *
 * Events to Dart (Nearby event stream): `ble_seen`, `ble_state`.
 */
@SuppressLint("MissingPermission")
object NearbyBle {
    const val TAG = "NEARBY"

    private val main = Handler(Looper.getMainLooper())
    private val uuid = ParcelUuid(UUID.fromString(NearbyBlePolicy.SERVICE_UUID))

    @Volatile private var app: Context? = null
    private var emit: ((Map<String, Any?>) -> Unit)? = null
    private var receiverOn = false
    private var running = false

    // What Dart asked for (setBleWanted).
    private var selfId: String? = null
    private var wanted: List<NearbyBlePolicy.Wanted> = emptyList()
    private var urgentSince = 0L
    private var searching = false
    private var host = false
    private var member = false
    private var onRouter = false
    private var foreground = false

    // Engine state.
    private var state = ""
    private var scanMode = "off"
    private var scanStartedAt = 0L
    private val scanStarts = ArrayList<Long>()
    private var throttleLogged = false
    private var advBytes: ByteArray? = null
    private var advMode = ""
    private var advOn = false
    private var counter = 0
    private var lastPacketKey = ""
    private val fails = NearbyBlePolicy.Fails()
    private var restLogged = false
    private val seen = NearbyBlePolicy.SeenGate()
    private var inCall = false

    private val tick = object : Runnable {
        override fun run() {
            if (!running) return
            apply("tick")
            main.postDelayed(this, NearbyBlePolicy.ROTATE_MS)
        }
    }

    private val adapterReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == BluetoothAdapter.ACTION_STATE_CHANGED) main.post { apply("adapter") }
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) { onResult(result) }
        override fun onBatchScanResults(results: MutableList<ScanResult>?) { results?.forEach { onResult(it) } }
        override fun onScanFailed(errorCode: Int) {
            main.post {
                Log.w(TAG, "BLE_SCAN failed code=$errorCode")
                scanMode = "off"
                scanStartedAt = 0L
                failed(SystemClock.elapsedRealtime())
            }
        }
    }

    private val advCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) { main.post { fails.ok() } }
        override fun onStartFailure(errorCode: Int) {
            main.post {
                Log.w(TAG, "BLE_ADV failed code=$errorCode")
                advOn = false
                advBytes = null
                // 3 = already started (harmless), 1 = data too large (a bug, rest).
                if (errorCode != AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED) failed(SystemClock.elapsedRealtime())
            }
        }
    }

    /** Called by NearbyRadio.ensure (safe to call again). */
    fun start(context: Context, events: (Map<String, Any?>) -> Unit) {
        main.post {
            try {
                app = context.applicationContext
                emit = events
                if (running) return@post
                running = true
                registerReceiver(context.applicationContext)
                apply("start")
                main.postDelayed(tick, NearbyBlePolicy.ROTATE_MS)
            } catch (e: Exception) {
                Log.w(TAG, "BLE_STATE start_failed ${e.javaClass.simpleName}")
            }
        }
    }

    /** Log out only. */
    fun stop(reason: String) {
        main.post {
            try {
                if (!running) return@post
                running = false
                main.removeCallbacks(tick)
                stopScan()
                stopAdvertising()
                val a = app
                if (receiverOn && a != null) { try { a.unregisterReceiver(adapterReceiver) } catch (_: Exception) {}; receiverOn = false }
                selfId = null
                wanted = emptyList()
                state = ""
                Log.i(TAG, "BLE_STATE state=stopped why=$reason")
            } catch (_: Exception) {}
        }
    }

    /** Permission answered / app opened: look again. */
    fun refresh(why: String) { main.post { apply(why) } }

    /** Live call voice started / ended (from NearbyRadio). */
    fun onCallVoice(live: Boolean) {
        main.post {
            inCall = live
            apply(if (live) "call_start" else "call_end")
        }
    }

    /** Dart: `setBleWanted`. Ids are 8 hex. Never throws. */
    fun setWanted(args: Map<*, *>?) {
        main.post {
            try {
                val now = SystemClock.elapsedRealtime()
                selfId = (args?.get("self") as? String)?.trim()?.lowercase()?.takeIf { NearbyBlePolicy.validId(it) }
                val list = ArrayList<NearbyBlePolicy.Wanted>()
                (args?.get("wanted") as? List<*>)?.forEach { item ->
                    val m = item as? Map<*, *> ?: return@forEach
                    val id = (m["id"] as? String)?.trim()?.lowercase()
                    if (NearbyBlePolicy.validId(id) && list.size < NearbyBlePolicy.MAX_WANTED) {
                        list.add(NearbyBlePolicy.Wanted(id!!, m["call"] == true, m["pair"] == true))
                    }
                }
                wanted = list
                val urgent = args?.get("urgent") == true
                urgentSince = if (!urgent) 0L else if (urgentSince > 0L) urgentSince else now
                searching = args?.get("searching") == true
                host = args?.get("host") == true
                member = args?.get("member") == true
                onRouter = args?.get("router") == true
                foreground = args?.get("fg") == true
                apply("wanted")
            } catch (_: Exception) {}
        }
    }

    /** Dart: `bleStatus`. */
    fun status(context: Context): Map<String, Any?> =
        mapOf("state" to stateNow(context.applicationContext), "sdk" to Build.VERSION.SDK_INT)

    fun scanPermission(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= 31) granted(context, Manifest.permission.BLUETOOTH_SCAN)
        else granted(context, Manifest.permission.ACCESS_FINE_LOCATION)

    fun advertisePermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < 31 || granted(context, Manifest.permission.BLUETOOTH_ADVERTISE)

    private fun granted(context: Context, p: String) =
        context.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    private fun adapter(context: Context): BluetoothAdapter? = try {
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    } catch (_: Exception) { null }

    private fun stateNow(a: Context): String = try {
        val ad = adapter(a)
        val hasBle = ad != null && a.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
        val enabled = ad?.isEnabled == true
        NearbyBlePolicy.stateWord(
            sdk = Build.VERSION.SDK_INT,
            hasBle = hasBle,
            enabled = enabled,
            scanPermission = scanPermission(a),
            advertisePermission = advertisePermission(a),
            canAdvertise = enabled && ad?.isMultipleAdvertisementSupported == true,
        )
    } catch (_: Exception) { "unsupported" }

    private fun apply(why: String) {
        val a = app ?: return
        if (!running) return
        try {
            val now = SystemClock.elapsedRealtime()
            val word = stateNow(a)
            if (word != state) {
                state = word
                Log.i(TAG, "BLE_STATE state=$word why=$why")
                emit?.invoke(mapOf("type" to "ble_state", "state" to word, "sdk" to Build.VERSION.SDK_INT))
                if (word != "on" && word != "scan_only") {
                    // Bluetooth off / no permission: Android stopped them already.
                    scanMode = "off"; scanStartedAt = 0L; advOn = false; advBytes = null
                }
            }
            if (word != "on" && word != "scan_only") return
            // Dart is the brain: no self id (not set up yet, Nearby off,
            // low battery with the app closed) = no scan, no advert.
            if (selfId == null) {
                if (scanMode != "off" || advOn) Log.i(TAG, "BLE_SCAN stop why=idle")
                stopScan(); stopAdvertising()
                return
            }
            if (fails.resting(now)) {
                if (!restLogged) { restLogged = true; Log.i(TAG, "BLE_REST min=${NearbyBlePolicy.REST_MS / 60_000}") }
                stopScan(); stopAdvertising()
                return
            }
            restLogged = false
            val urgent = NearbyBlePolicy.urgentNow(urgentSince, now)
            applyScan(a, NearbyBlePolicy.scanMode(inCall, urgent, foreground), now)
            if (word == "on") applyAdvertising(a, urgent, now) else stopAdvertising()
        } catch (e: Exception) {
            Log.w(TAG, "BLE_STATE error=${e.javaClass.simpleName}")
        }
    }

    private fun applyScan(a: Context, mode: String, now: Long) {
        if (mode == "off") {
            if (scanMode != "off") { stopScan(); Log.i(TAG, "BLE_SCAN stop why=call") }
            return
        }
        val restart = NearbyBlePolicy.restartDue(scanStartedAt, now)
        if (mode == scanMode && !restart) return
        if (!NearbyBlePolicy.scanStartAllowed(scanStarts, now)) {
            if (!throttleLogged) { throttleLogged = true; Log.i(TAG, "BLE_THROTTLED wait_ms=${NearbyBlePolicy.scanWaitMs(scanStarts, now)}") }
            return // the 5 s tick tries again
        }
        throttleLogged = false
        val scanner = adapter(a)?.bluetoothLeScanner ?: return
        if (scanMode != "off") { try { scanner.stopScan(scanCallback) } catch (_: Exception) {} }
        val settings = ScanSettings.Builder().setScanMode(
            when (mode) {
                "low_latency" -> ScanSettings.SCAN_MODE_LOW_LATENCY
                "balanced" -> ScanSettings.SCAN_MODE_BALANCED
                else -> ScanSettings.SCAN_MODE_LOW_POWER
            }
        ).build()
        val filter = ScanFilter.Builder()
            .setServiceData(uuid, byteArrayOf((NearbyBlePolicy.VERSION shl 4).toByte()), byteArrayOf(0xF0.toByte()))
            .build()
        scanStarts.add(now)
        try {
            scanner.startScan(listOf(filter), settings, scanCallback)
            scanMode = mode
            scanStartedAt = now
            Log.i(TAG, "BLE_SCAN start mode=$mode${if (restart) " why=restart" else ""}")
        } catch (e: Exception) {
            Log.w(TAG, "BLE_SCAN start_failed ${e.javaClass.simpleName}")
            scanMode = "off"
            failed(now)
        }
    }

    private fun stopScan() {
        if (scanMode == "off") return
        val a = app
        try { if (a != null) adapter(a)?.bluetoothLeScanner?.stopScan(scanCallback) } catch (_: Exception) {}
        scanMode = "off"
        scanStartedAt = 0L
    }

    private fun applyAdvertising(a: Context, urgent: Boolean, now: Long) {
        val self = selfId
        if (self == null) { stopAdvertising(); return }
        val w = NearbyBlePolicy.pick(wanted, System.currentTimeMillis())
        val base = NearbyBlePolicy.Packet(
            id8 = self, wanted8 = w?.id8, host = host, member = member,
            searching = searching, onRouter = onRouter, call = w?.call == true, pairHost = w?.pairHost == true,
        )
        val key = base.toString()
        if (key != lastPacketKey) { lastPacketKey = key; counter = (counter + 1) and 0x3f }
        val bytes = NearbyBlePolicy.encode(base.copy(counter = counter)) ?: run { stopAdvertising(); return }
        val mode = NearbyBlePolicy.advMode(urgent, inCall)
        if (advOn && mode == advMode && advBytes?.contentEquals(bytes) == true) return
        val adv = adapter(a)?.bluetoothLeAdvertiser ?: return
        if (advOn) { try { adv.stopAdvertising(advCallback) } catch (_: Exception) {} }
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(if (mode == "low_latency") AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY else AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(false)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceData(uuid, bytes)
            .build()
        try {
            adv.startAdvertising(settings, data, advCallback)
            val modeChanged = mode != advMode
            advOn = true
            advBytes = bytes
            advMode = mode
            if (modeChanged) Log.i(TAG, "BLE_ADV start mode=$mode")
        } catch (e: Exception) {
            Log.w(TAG, "BLE_ADV start_failed ${e.javaClass.simpleName}")
            advOn = false
            advBytes = null
            failed(now)
        }
    }

    private fun stopAdvertising() {
        if (!advOn) return
        val a = app
        try { if (a != null) adapter(a)?.bluetoothLeAdvertiser?.stopAdvertising(advCallback) } catch (_: Exception) {}
        advOn = false
        advBytes = null
        advMode = ""
    }

    private fun failed(now: Long) {
        if (fails.failed(now)) {
            Log.i(TAG, "BLE_REST min=${NearbyBlePolicy.REST_MS / 60_000} why=fails")
            restLogged = true
            stopScan()
            stopAdvertising()
        }
    }

    private fun onResult(result: ScanResult?) {
        try {
            val data = result?.scanRecord?.getServiceData(uuid) ?: return
            val p = NearbyBlePolicy.decode(data) ?: return
            val rssi = result.rssi
            main.post {
                if (!running || p.id8 == selfId) return@post
                val now = SystemClock.elapsedRealtime()
                if (!seen.shouldEmit(p, now)) return@post
                if (seen.shouldLog(p.id8, now)) {
                    Log.i(TAG, "BLE_SEEN id=${p.id8} wants_me=${yn(p.wanted8 != null && p.wanted8 == selfId)} host=${yn(p.host)} pair=${yn(p.pairHost)} call=${yn(p.call)} searching=${yn(p.searching)} rssi=$rssi")
                }
                emit?.invoke(mapOf(
                    "type" to "ble_seen",
                    "id" to p.id8,
                    "wanted" to p.wanted8,
                    "host" to p.host,
                    "member" to p.member,
                    "searching" to p.searching,
                    "router" to p.onRouter,
                    "call" to p.call,
                    "pair" to p.pairHost,
                    "rssi" to rssi,
                ))
            }
        } catch (_: Exception) {}
    }

    private fun registerReceiver(context: Context) {
        if (receiverOn) return
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(adapterReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else context.registerReceiver(adapterReceiver, filter)
        receiverOn = true
    }

    private fun yn(b: Boolean) = if (b) "y" else "n"
}
