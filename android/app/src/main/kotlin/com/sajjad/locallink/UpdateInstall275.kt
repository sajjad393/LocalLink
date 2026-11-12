package com.sajjad.locallink

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

/**
 * Bundle 275: the old phone's quiet update - install part.
 *
 * - `dir`: `<cache>/update275` (app cache: no storage permission; Android
 *   may also clear it).
 * - `check`: the file is inside that folder, the size matches the offer and
 *   it is a `com.sajjad.linkup` APK. Android checks the signing key itself
 *   when installing (a different key is refused).
 * - `canInstall` / `openSettings`: "Install unknown apps" for LinkUp. The
 *   settings page opens ONLY when the user taps Install.
 * - `install`: Android's own "Update" screen (always asks the user).
 * Never throws to Dart.
 */
object UpdateInstall275 {
    private const val TAG = "APP_UPDATE_275"
    const val PACKAGE = "com.sajjad.linkup"
    private const val MIME = "application/vnd.android.package-archive"

    fun dir(activity: Activity): String = try {
        val d = File(activity.cacheDir, "update275")
        if (!d.exists()) d.mkdirs()
        d.absolutePath
    } catch (_: Exception) { "" }

    private fun inside(activity: Activity, path: String): File? {
        if (path.isEmpty()) return null
        return try {
            val base = File(activity.cacheDir, "update275").canonicalFile
            val f = File(path).canonicalFile
            if (f.parentFile == base && f.isFile) f else null
        } catch (_: Exception) { null }
    }

    fun check(activity: Activity, path: String, size: Long): Map<String, Any?> {
        val f = inside(activity, path) ?: return mapOf("ok" to false, "reason" to "not_found")
        if (size > 0 && f.length() != size) return mapOf("ok" to false, "reason" to "size")
        val pkg = try {
            activity.packageManager.getPackageArchiveInfo(f.absolutePath, 0)?.packageName
        } catch (_: Exception) { null }
        if (pkg != PACKAGE) return mapOf("ok" to false, "reason" to "package")
        return mapOf("ok" to true)
    }

    fun canInstall(activity: Activity): Boolean = try {
        if (Build.VERSION.SDK_INT >= 26) activity.packageManager.canRequestPackageInstalls() else true
    } catch (_: Exception) { false }

    fun openSettings(activity: Activity): Boolean = try {
        if (Build.VERSION.SDK_INT >= 26) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")))
            true
        } else false
    } catch (e: Exception) {
        Log.w(TAG, "settings error=${e.javaClass.simpleName}")
        false
    }

    fun install(activity: Activity, path: String): Boolean {
        val f = inside(activity, path) ?: return false
        return try {
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.update275", f)
            val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, MIME)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(i)
            Log.i(TAG, "installer open size=${f.length()}")
            true
        } catch (e: Exception) {
            Log.w(TAG, "install error=${e.javaClass.simpleName}")
            false
        }
    }
}
