package com.sajjad.locallink

/**
 * Bundle 179 (3): can a call notification show, and how? Pure (Android
 * importance numbers are passed in: 0 none, 1 min, 2 low, 3 default, 4 high).
 */
object CallAlertPolicy {
    const val OK = "ok"
    const val PERMISSION = "permission"
    const val APP_OFF = "app_off"
    const val CATEGORY_OFF = "category_off"
    const val LOCKSCREEN_OFF = "lockscreen_off"

    const val MODE_FULL_SCREEN = "full_screen"
    const val MODE_POPUP = "popup"

    private const val IMPORTANCE_DEFAULT = 3

    /**
     * [channelImportance] null = unknown / Android 7. [fullScreenAllowed]
     * null = Android 13 and older (always allowed).
     */
    fun state(permissionGranted: Boolean, appEnabled: Boolean, channelImportance: Int?, fullScreenAllowed: Boolean?): String = when {
        !permissionGranted -> PERMISSION
        !appEnabled -> APP_OFF
        channelImportance != null && channelImportance < IMPORTANCE_DEFAULT -> CATEGORY_OFF
        fullScreenAllowed == false -> LOCKSCREEN_OFF
        else -> OK
    }

    /** No notification can show at all (the phone still rings). */
    fun blocked(state: String): Boolean = state == PERMISSION || state == APP_OFF || state == CATEGORY_OFF

    /**
     * Full screen only when Android allows it. Some phones (Realme / Oppo)
     * drop the WHOLE notification when full screen is asked but not allowed,
     * so then a normal pop-up with Accept / Reject is posted instead.
     */
    fun mode(fullScreenAllowed: Boolean?): String = if (fullScreenAllowed == false) MODE_POPUP else MODE_FULL_SCREEN
}
