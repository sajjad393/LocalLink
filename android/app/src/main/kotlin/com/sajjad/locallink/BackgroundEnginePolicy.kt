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

    /** Reasons that leave the phone without messages until the app is opened. */
    fun showReconnectNotice(reason: String?): Boolean =
        reason == "error" || reason == "new_version_not_opened"
}
