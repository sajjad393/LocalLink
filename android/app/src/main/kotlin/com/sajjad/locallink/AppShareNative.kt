package com.sajjad.locallink

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bundle 210: "Share LinkUp" native side (channel `locallink/app_share`).
 *
 * - `apkInfo`: path + size + version of the installed APK (one file only).
 * - `startShare` / `stopShare` / `shareStatus`: the local hotspot with owner
 *   "share" (re-uses the mesh one when it is already on).
 * - `addresses`, `battery`, `keepScreenOn`, `open*Settings`.
 *
 * Never logs the hotspot name or password. Never throws to Dart.
 */
object AppShareNative {
    const val CHANNEL = "locallink/app_share"
    private const val TAG = "SHARE_APP"
    private val main = Handler(Looper.getMainLooper())

    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "apkInfo" -> result.success(apkInfo(activity))
                "startShare" -> startShare(activity, result)
                "stopShare" -> {
                    localNet(activity)?.stopHotspot(AppSharePolicy.OWNER_SHARE, call.argument<String>("reason") ?: "user")
                    Log.i(TAG, "stop reason=${call.argument<String>("reason") ?: "user"}")
                    result.success(null)
                }
                "shareStatus" -> result.success(localNet(activity)?.shareStatus() ?: mapOf("on" to false, "share" to false))
                "addresses" -> result.success(addressMap(activity))
                "battery" -> {
                    val (charging, level) = NearbyRadio.battery(activity)
                    result.success(mapOf("charging" to charging, "level" to level))
                }
                "keepScreenOn" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    activity.runOnUiThread {
                        try {
                            if (on) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } catch (_: Exception) {}
                    }
                    result.success(null)
                }
                "openHotspotSettings" -> result.success(openFirst(activity, listOf(
                    Intent("android.settings.TETHER_SETTINGS"),
                    Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.TetherSettings")),
                    Intent(Settings.ACTION_WIRELESS_SETTINGS),
                    Intent(Settings.ACTION_WIFI_SETTINGS),
                )))
                "openWifiSettings" -> result.success(openFirst(activity, listOfNotNull(
                    if (Build.VERSION.SDK_INT >= 29) Intent(Settings.Panel.ACTION_WIFI) else null,
                    Intent(Settings.ACTION_WIFI_SETTINGS),
                )))
                "openLocationSettings" -> result.success(openFirst(activity, listOf(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))))
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.w(TAG, "channel error method=${call.method} error=${e.javaClass.simpleName}")
            try { result.success(mapOf("ok" to false, "reason" to "error")) } catch (_: Exception) {}
        }
    }

    /** Clears the keep-screen-on flag (screen closed). */
    fun release(activity: Activity) {
        try { activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) } catch (_: Exception) {}
    }

    private fun localNet(context: Context): LocalNetManager? {
        NearbyRadio.localNet?.let { return it }
        // No Wi-Fi Direct (or Nearby not set up yet): a manager with no tags.
        return try {
            LocalNetManager.bind(context.applicationContext, { NearbyRadio.tags }) { _ -> }
        } catch (_: Exception) { null }
    }

    private fun apkInfo(context: Context): Map<String, Any?> {
        val ai = context.applicationInfo
        val path = ai.sourceDir
        val f = if (path != null) File(path) else null
        if (f == null || !f.canRead()) return mapOf("ok" to false, "reason" to "apk_missing")
        val pi = try { context.packageManager.getPackageInfo(context.packageName, 0) } catch (_: Exception) { null }
        @Suppress("DEPRECATION")
        val code: Long = if (pi == null) 0L else if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else pi.versionCode.toLong()
        return mapOf(
            "ok" to true,
            "path" to path,
            "size" to f.length(),
            "version_name" to (pi?.versionName ?: ""),
            "version_code" to code,
            "split" to AppSharePolicy.isSplit(ai.splitSourceDirs),
            "min_sdk" to (if (Build.VERSION.SDK_INT >= 24) ai.minSdkVersion else 0),
        )
    }

    private fun startShare(activity: Activity, result: MethodChannel.Result) {
        val app = activity.applicationContext
        val done = AtomicBoolean(false)
        // Bundle 223 (E): the 15 s limit is for starting the hotspot only;
        // the address wait (up to 10 s) has its own limit.
        val hotspotUp = AtomicBoolean(false)
        fun reply(map: Map<String, Any?>) {
            if (!done.compareAndSet(false, true)) return
            main.post { try { result.success(map) } catch (_: Exception) {} }
        }
        if (!NearbyRadio.hasPermission(app)) { reply(mapOf("ok" to false, "reason" to "permission")); return }
        if (Build.VERSION.SDK_INT <= 32 && !locationOn(app)) { reply(mapOf("ok" to false, "reason" to "location_off")); return }
        val ln = localNet(activity)
        if (ln == null) { reply(mapOf("ok" to false, "reason" to "no_radio")); return }
        val before = interfaces()
        Log.i(TAG, "start on=${ln.hotspotOn()} before=${AppSharePolicy.listForLog(before)}")
        val why = ln.startHotspot(AppSharePolicy.OWNER_SHARE) { info ->
            if (info["ok"] != true) {
                val reason = AppSharePolicy.reasonFor(info["reason"]?.toString())
                Log.i(TAG, "failed reason=$reason")
                reply(mapOf("ok" to false, "reason" to reason))
                return@startHotspot
            }
            hotspotUp.set(true)
            waitForAddress(app, before, System.currentTimeMillis()) { ip, iface ->
                Log.i(TAG, "on reused=${info["reused"]} iface=${iface ?: "?"} ip_found=${ip != null}")
                reply(info + mapOf("ip" to ip, "addresses" to addressMap(app)["list"]))
            }
        }
        if (why != null) {
            val reason = AppSharePolicy.reasonFor(why)
            Log.i(TAG, "failed reason=$reason")
            reply(mapOf("ok" to false, "reason" to reason))
            return
        }
        main.postDelayed({
            if (!done.get() && !hotspotUp.get()) {
                Log.i(TAG, "failed reason=timeout")
                try { ln.stopHotspot(AppSharePolicy.OWNER_SHARE, "timeout") } catch (_: Exception) {}
                reply(mapOf("ok" to false, "reason" to "timeout"))
            }
        }, AppSharePolicy.START_TIMEOUT_MS)
    }

    private fun waitForAddress(context: Context, before: Map<String, String>, startedAt: Long, done: (String?, String?) -> Unit) {
        val now = interfaces()
        // Bundle 223 (E): the router address (if any) decides about wlan0.
        val ip = AppSharePolicy.pickHotspotIp(before, now, wifiIp(context))
        val ms = System.currentTimeMillis() - startedAt
        if (ip != null || ms >= AppSharePolicy.ADDRESS_WAIT_MS) {
            val iface = now.entries.firstOrNull { it.value == ip }?.key
            // Bundle 223 (E): the app writes ip_wait / ip_none; here only
            // what Android saw (for the next log).
            Log.i(TAG, "addr ms=$ms found=${ip ?: "none"} list=${AppSharePolicy.listForLog(now)}")
            done(ip, iface)
            return
        }
        main.postDelayed({ waitForAddress(context, before, startedAt, done) }, AppSharePolicy.ADDRESS_STEP_MS)
    }

    /** iface → first IPv4 (up interfaces only). */
    private fun interfaces(): Map<String, String> = try {
        val out = LinkedHashMap<String, String>()
        NetworkInterface.getNetworkInterfaces()?.toList().orEmpty().forEach { ni ->
            if (!ni.isUp || ni.isLoopback) return@forEach
            val ip = ni.inetAddresses.toList().filterIsInstance<Inet4Address>().firstOrNull()?.hostAddress
            if (ip != null) out[ni.name] = ip
        }
        out
    } catch (_: Exception) { emptyMap() }

    private fun addressMap(context: Context): Map<String, Any?> {
        val list = interfaces().map { (iface, ip) ->
            mapOf("iface" to iface, "ip" to ip, "hotspot" to AppSharePolicy.looksLikeHotspot(iface))
        }
        return mapOf("list" to list, "wifi_ip" to wifiIp(context))
    }

    /** The normal Wi-Fi (router) address, when connected. */
    private fun wifiIp(context: Context): String? = try {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        var found: String? = null
        @Suppress("DEPRECATION")
        for (n in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(n) ?: continue
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue
            val lp = cm.getLinkProperties(n) ?: continue
            if (lp.interfaceName?.startsWith("p2p") == true) continue
            val ip = lp.linkAddresses.map { it.address }.filterIsInstance<Inet4Address>().firstOrNull()?.hostAddress
            if (ip != null && AppSharePolicy.isPrivateV4(ip)) { found = ip; break }
        }
        found
    } catch (_: Exception) { null }

    private fun locationOn(context: Context): Boolean = try {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        if (Build.VERSION.SDK_INT >= 28) lm.isLocationEnabled
        else @Suppress("DEPRECATION") (Settings.Secure.getInt(context.contentResolver, Settings.Secure.LOCATION_MODE, 0) != 0)
    } catch (_: Exception) { true }

    private fun openFirst(activity: Activity, intents: List<Intent>): Boolean {
        for (i in intents) {
            try {
                activity.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {}
        }
        return false
    }
}
