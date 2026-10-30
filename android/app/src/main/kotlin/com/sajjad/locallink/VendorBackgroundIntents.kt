package com.sajjad.locallink

/**
 * Bundle 163 (5.6): the brand's own "background / autostart" page, tried in
 * order. Pure data so it can be unit tested; MainActivity starts them and
 * falls back to the app's info page (Battery lives there on most phones).
 */
object VendorBackgroundIntents {
    val BRANDS = listOf("xiaomi", "samsung", "oppo", "vivo", "huawei", "transsion", "zte", "other")

    fun candidates(brand: String): List<Pair<String, String>> = when (brand.lowercase()) {
        "xiaomi" -> listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        )
        "samsung" -> listOf(
            "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
            "com.samsung.android.sm" to "com.samsung.android.sm.ui.battery.BatteryActivity",
        )
        "oppo" -> listOf(
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
        )
        "vivo" -> listOf(
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
        )
        "huawei" -> listOf(
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            "com.hihonor.systemmanager" to "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        )
        "transsion" -> listOf(
            "com.transsion.phonemanager" to "com.transsion.phonemanager.appautostart.AutoStartActivity",
            "com.transsion.phonemanager" to "com.transsion.phonemanager.FunctionActivity",
        )
        "zte" -> listOf(
            "com.zte.heartyservice" to "com.zte.heartyservice.autorun.AppAutoRunManager",
        )
        else -> emptyList()
    }
}
