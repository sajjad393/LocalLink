package com.sajjad.locallink

/** Bundle 176 (3): the app-wide hand-over slot (see [CallHandoverSlot]). */
object CallHandover {
    private const val TAG = "LocalLinkCall"
    private val slot = CallHandoverSlot()

    fun park(callId: String, json: String) {
        val ok = slot.park(callId, json, android.os.SystemClock.elapsedRealtime())
        android.util.Log.i(TAG, "CALL_HANDOVER_PARK call=$callId ok=$ok")
    }

    fun take(): String? {
        val json = slot.take(android.os.SystemClock.elapsedRealtime())
        if (json != null) android.util.Log.i(TAG, "CALL_HANDOVER_TAKE ok=true")
        return json
    }

    fun clear(callId: String) = slot.clear(callId)

    /** Channel "locallink/call_handover" (same in MainActivity and the no-screen engine). */
    fun handle(call: io.flutter.plugin.common.MethodCall, result: io.flutter.plugin.common.MethodChannel.Result) {
        when (call.method) {
            "park" -> {
                park(call.argument<String>("call_id")?.trim().orEmpty(), call.argument<String>("invite").orEmpty())
                result.success(null)
            }
            "take" -> result.success(take())
            "clear" -> { clear(call.argument<String>("call_id")?.trim().orEmpty()); result.success(null) }
            else -> result.notImplemented()
        }
    }

    const val CHANNEL = "locallink/call_handover"
}
