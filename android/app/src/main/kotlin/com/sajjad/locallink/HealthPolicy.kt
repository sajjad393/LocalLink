package com.sajjad.locallink

/** Bundle 175 (5): pure rules for the health check (unit tested). */
object HealthPolicy {
    enum class Action { NOTHING, ENGINE, RESTART }

    fun decide(enabled: Boolean, serviceRunning: Boolean, appOpen: Boolean): Action = when {
        !enabled -> Action.NOTHING
        !serviceRunning -> Action.RESTART
        // Running but nobody reads its events: make sure the no-screen engine is there.
        !appOpen -> Action.ENGINE
        else -> Action.NOTHING
    }
}
