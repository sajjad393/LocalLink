package com.sajjad.locallink

/**
 * Bundle 196 (12b): the pair packet kinds this app sends and accepts.
 * "wait" = "your Add arrived; the other person must accept first"
 * (their profile is private). Older apps drop "wait" (bad kind) silently.
 */
object PairKind {
    const val REQUEST = "request"
    const val ACCEPT = "accept"
    const val WAIT = "wait"

    fun valid(kind: String?): Boolean = kind == REQUEST || kind == ACCEPT || kind == WAIT
}
