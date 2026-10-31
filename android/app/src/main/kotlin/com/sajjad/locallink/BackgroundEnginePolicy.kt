package com.sajjad.locallink

/**
 * Bundle 169 (4.3): may the app's own background engine start after a reboot?
 * Pure rules (no Android calls) so they are unit-tested on the JVM.
 */
object BackgroundEnginePolicy {
    /** Returns null when the engine should start, else the reason it does not. */
    fun skipReason(
        bootStartOk: Boolean,
        appOpen: Boolean,
        running: Boolean,
        openedVersion: Long,
        currentVersion: Long,
    ): String? = when {
        !bootStartOk -> "service_not_started"
        appOpen -> "app_open"
        running -> "running"
        // Never opened on this phone: no account yet, nothing to receive.
        openedVersion <= 0L -> "never_opened"
        // A new app version runs its database upgrade with the app open,
        // never half-way in the background.
        openedVersion != currentVersion -> "new_version_not_opened"
        else -> null
    }

    /**
     * Bundle 175 (3): may the engine start because the screen went away
     * (swipe, Back exit, restart after a kill, an event nobody reads)?
     * Returns null when it should start, else the reason it does not.
     */
    fun noScreenSkipReason(
        enabled: Boolean,
        serviceRunning: Boolean,
        appOpen: Boolean,
        running: Boolean,
        openedVersion: Long,
        currentVersion: Long,
        idleBlocked: Boolean,
    ): String? = when {
        !enabled -> "background_off"
        appOpen -> "app_open"
        running -> "running"
        !serviceRunning -> "service_not_running"
        openedVersion <= 0L -> "never_opened"
        openedVersion != currentVersion -> "new_version_not_opened"
        // Dart said there is nothing to do (no account / signed out): don't
        // start it again and again for every nearby event.
        idleBlocked -> "idle_recently"
        else -> null
    }

    /** After Dart said "idle", no-screen starts wait this long. */
    const val IDLE_BLOCK_MS = 10 * 60_000L

    /** Reasons that leave the phone without messages until the app is opened. */
    fun showReconnectNotice(reason: String?): Boolean =
        reason == "error" || reason == "new_version_not_opened"
}
