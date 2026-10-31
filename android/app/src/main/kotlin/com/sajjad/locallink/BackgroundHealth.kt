package com.sajjad.locallink

import android.content.Context
import android.util.Log
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Bundle 175 (5, 6): background health.
 *
 * - The "Keep running" switch, mirrored on the native side (default ON; the
 *   app keeps it locked ON) so reboot / health checks can respect it.
 * - WorkManager only CHECKS and ASKS the existing service to start. It never
 *   opens sockets or moves messages.
 * - On Android 12+ a background start can be refused (unless the battery
 *   exemption is on). Then the quiet "Tap to reconnect" notice is shown.
 */
object BackgroundHealth {
    private const val TAG = "LocalLinkBoot"
    private const val PREFS = "locallink_background"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_LAST_DENY = "last_deny"
    private const val KEY_LAST_DENY_AT = "last_deny_at"
    const val HEALTH_WORK = "locallink_health"
    const val RECOVER_WORK = "locallink_recover"

    fun isEnabled(context: Context): Boolean = try {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, true)
    } catch (_: Exception) { true }

    fun setEnabled(context: Context, on: Boolean) {
        try { context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, on).apply() } catch (_: Exception) {}
    }

    fun noteDenied(context: Context, reason: String) {
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_LAST_DENY, reason).putLong(KEY_LAST_DENY_AT, System.currentTimeMillis()).apply()
        } catch (_: Exception) {}
    }

    fun lastDenied(context: Context): String? = try {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_LAST_DENY, null)
    } catch (_: Exception) { null }

    fun clearDenied(context: Context) {
        try { context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_LAST_DENY).remove(KEY_LAST_DENY_AT).apply() } catch (_: Exception) {}
    }

    /** Every 15 min (Android's minimum). KEEP: one schedule only. */
    fun schedule(context: Context) {
        try {
            val request = PeriodicWorkRequest.Builder(HealthWorker::class.java, 15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniquePeriodicWork(HEALTH_WORK, ExistingPeriodicWorkPolicy.KEEP, request)
        } catch (e: Exception) {
            Log.w(TAG, "HEALTH_SCHEDULE_FAILED reason=${e.javaClass.simpleName}")
        }
    }

    /** One try about a minute after Android refused a start. REPLACE: never piles up. */
    fun recoverSoon(context: Context, reason: String) {
        noteDenied(context, reason)
        try {
            val request = OneTimeWorkRequest.Builder(HealthWorker::class.java)
                .setInputData(Data.Builder().putString(HealthWorker.KEY_TRIGGER, "recover").build())
                .setInitialDelay(1, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniqueWork(RECOVER_WORK, ExistingWorkPolicy.REPLACE, request)
        } catch (e: Exception) {
            Log.w(TAG, "HEALTH_RECOVER_FAILED reason=${e.javaClass.simpleName}")
        }
    }

    /** The check itself (also used by tests through [HealthPolicy]). */
    fun check(context: Context, trigger: String) {
        val app = context.applicationContext
        val action = HealthPolicy.decide(
            enabled = isEnabled(app),
            serviceRunning = LocalLinkTransportService.isRunning(),
            appOpen = MainActivity.isOpen(),
        )
        when (action) {
            HealthPolicy.Action.NOTHING -> Log.i(TAG, "HEALTH_OK trigger=$trigger running=${LocalLinkTransportService.isRunning()}")
            HealthPolicy.Action.ENGINE -> {
                Log.i(TAG, "HEALTH_OK trigger=$trigger running=true engine=check")
                BackgroundEngine.startNoScreen(app, "health")
            }
            HealthPolicy.Action.RESTART -> {
                val failure = LocalLinkTransportService.startFromHealth(app)
                if (failure == null) {
                    Log.i(TAG, "HEALTH_RESTART ok trigger=$trigger")
                    clearDenied(app)
                } else {
                    Log.w(TAG, "HEALTH_RESTART denied trigger=$trigger reason=$failure")
                    noteDenied(app, failure)
                    try { LocalLinkNotificationManager.showBootReconnect(app) } catch (_: Exception) {}
                }
            }
        }
    }
}

class HealthWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        try {
            BackgroundHealth.check(applicationContext, inputData.getString(KEY_TRIGGER) ?: "periodic")
        } catch (e: Throwable) {
            Log.w("LocalLinkBoot", "HEALTH_FAILED reason=${e.javaClass.simpleName}")
        }
        return Result.success()
    }

    companion object { const val KEY_TRIGGER = "trigger" }
}
