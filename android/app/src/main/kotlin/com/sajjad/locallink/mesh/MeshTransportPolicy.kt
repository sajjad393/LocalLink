package com.sajjad.locallink.mesh

/**
 * Shared transport-level constants and validation. Both LAN and Wi-Fi Direct
 * ultimately carry the same MeshPacket through MeshRouter.
 */
object MeshTransportPolicy {
    const val WIFI_DIRECT: String = "wifi_direct"
    const val LAN: String = "lan"
    /** Bundle 161: a link over another Wi-Fi network this phone joined as a
     *  normal Wi-Fi user (another nearby group, or a LocalLink hotspot). */
    const val LOCAL_NET: String = "local_net"

    /** Bundle 201 (B): is this link already our link to the Wi-Fi Direct host
     *  at [owner]? A Wi-Fi Direct client link keeps no owner address (null
     *  means "the other side is the host" elsewhere), so it is matched by the
     *  remote address of its socket. Before 201 the check never matched and
     *  the client dialed the host again every ~5 s, replacing a good link. */
    fun linksOwner(owner: String?, ownerAddress: String?, transportName: String, remoteAddress: String?): Boolean {
        val o = owner?.trim()?.removePrefix("/").orEmpty()
        if (o.isEmpty()) return false
        if (ownerAddress?.trim()?.removePrefix("/") == o) return true
        return transportName == WIFI_DIRECT && remoteAddress?.trim()?.removePrefix("/") == o
    }

    const val WIFI_DIRECT_PORT: Int = 8988
    const val LAN_PORT: Int = 8989
    const val LAN_DISCOVERY_PORT: Int = 8990
    /** Bundle 161: listening port for [LOCAL_NET] links. */
    const val LOCAL_NET_PORT: Int = 8991

    const val DISCOVERY_PROTOCOL_VERSION: Int = 1
    const val LAN_BEACON_INTERVAL_MS: Long = 3_000L
    const val LAN_ENDPOINT_RETENTION_MS: Long = 12_000L
    const val SOCKET_CONNECT_TIMEOUT_MS: Int = 3_000
    const val HEARTBEAT_INTERVAL_MS: Long = 5_000L
    const val HEARTBEAT_TIMEOUT_MS: Long = 15_000L
    // Transient write failures tolerated before a physical link is declared
    // dead. Mobile Wi-Fi power-save routinely stalls a single socket write;
    // tearing the whole link down for one stalled frame is what made calls
    // and ticks flap. Two+ consecutive failures (or EOF) is what counts.
    const val WRITE_STRIKE_LIMIT: Int = 3

    // Bundle 160 (plan 160.3): quieter Local Wi-Fi with many phones.
    const val LAN_BEACON_MEDIUM_MS: Long = 10_000L
    const val LAN_BEACON_LARGE_MS: Long = 15_000L
    const val LAN_MEDIUM_PHONES: Int = 10
    const val LAN_LARGE_PHONES: Int = 50
    /** D12: direct LAN links to contacts this phone opens by itself. More
     *  are opened only when a message needs one (and incoming links are
     *  always accepted). Relay neighbours (3-5) are counted separately. */
    const val MAX_DIRECT_LAN_LINKS: Int = 30

    /** Beacon every 3 s with < 10 phones, 10 s with 10-50, 15 s with 50+. */
    /** Bundle 223 (K): wait after "Network unreachable" (Wi-Fi off). */
    const val LAN_BEACON_BACKOFF_MS: Long = 15_000L

    /** Bundle 223 (K): "Network is unreachable" / no route (Wi-Fi off). */
    fun isUnreachable(message: String?): Boolean {
        val m = message ?: return false
        return m.contains("ENETUNREACH") || m.contains("Network is unreachable") ||
            m.contains("EHOSTUNREACH") || m.contains("No route to host")
    }

    /**
     * Bundle 223 (K): with Wi-Fi off every beacon failed every ~4 s and sent
     * an error to Dart (48 in 3 min on the ZTE). After an unreachable error
     * the beacon waits [LAN_BEACON_BACKOFF_MS] and the error is reported
     * ONCE; a good send or a network change brings the normal tier back.
     */
    class LanBeaconBackoff {
        var paused: Boolean = false
            private set

        /** A send failed. True = report it (first unreachable, or any other error). */
        fun onError(unreachable: Boolean): Boolean {
            if (!unreachable) return true
            if (paused) return false
            paused = true
            return true
        }

        /** A send worked or the network changed. True = it was paused (log "resumed"). */
        fun onOk(): Boolean {
            val was = paused
            paused = false
            return was
        }

        fun nextDelayMs(normalMs: Long): Long = if (paused) LAN_BEACON_BACKOFF_MS else normalMs
    }

    /** Bundle 224 (B1): the result of one beacon round over all addresses. */
    enum class BeaconOutcome { OK, PAUSE, REPORT }

    /** OK when at least one address worked (or there was none, as before);
     *  PAUSE only when every address failed with "unreachable"; REPORT for
     *  any other error. */
    fun beaconOutcome(okCount: Int, unreachableCount: Int, otherCount: Int): BeaconOutcome = when {
        okCount > 0 -> BeaconOutcome.OK
        otherCount > 0 -> BeaconOutcome.REPORT
        unreachableCount > 0 -> BeaconOutcome.PAUSE
        else -> BeaconOutcome.OK
    }

    /** Bundle 224 (B2): a Wi-Fi Direct group formed, or our role changed. */
    fun wdGroupChanged(wasConnected: Boolean?, wasOwner: Boolean?, connected: Boolean, owner: Boolean): Boolean =
        connected && (wasConnected != true || wasOwner != owner)

    fun lanBeaconIntervalMs(phonesSeen: Int): Long = when {
        phonesSeen >= LAN_LARGE_PHONES -> LAN_BEACON_LARGE_MS
        phonesSeen >= LAN_MEDIUM_PHONES -> LAN_BEACON_MEDIUM_MS
        else -> LAN_BEACON_INTERVAL_MS
    }

    /** ±20% jitter so 50 phones don't all shout at the same moment.
     *  [unit] is a random number in [0, 1). */
    fun jitteredBeaconMs(phonesSeen: Int, unit: Double): Long {
        val base = lanBeaconIntervalMs(phonesSeen)
        val u = unit.coerceIn(0.0, 1.0)
        return (base * (0.8 + 0.4 * u)).toLong()
    }

    /** A phone is forgotten after missing about 3 beacons (never < 12 s). */
    fun lanEndpointRetentionMs(phonesSeen: Int): Long =
        maxOf(LAN_ENDPOINT_RETENTION_MS, lanBeaconIntervalMs(phonesSeen) * 12 / 10 * 3)

    /** D12: may this phone dial a contact it sees on Local Wi-Fi by itself? */
    fun mayDialContact(directLanLinks: Int, needed: Boolean): Boolean =
        needed || directLanLinks < MAX_DIRECT_LAN_LINKS

    /** One logical active link is kept per peer; LAN is preferred when both links exist. */
    fun transportPriority(name: String): Int = when (name) {
        LAN -> 20
        LOCAL_NET -> 15
        WIFI_DIRECT -> 10
        else -> 0
    }

    fun isSupportedTransport(name: String): Boolean =
        name == LAN || name == WIFI_DIRECT || name == LOCAL_NET

    fun isValidPort(port: Int): Boolean = port in 1..65_535

    fun shouldReplaceExistingTransport(existing: String, incoming: String): Boolean {
        if (existing == incoming) return true
        return transportPriority(incoming) > transportPriority(existing)
    }
}

/**
 * Bundle 224 (G2): the "RELAY file stalled" line. The first [FIRST_LINES]
 * stalls are logged as before; after that at most one line per [EVERY_MS]
 * per transfer. Log only - the resend itself is unchanged.
 */
object FileStallLog224 {
    const val FIRST_LINES = 20
    const val EVERY_MS = 10 * 60 * 1000L

    fun shouldLog(stalls: Int, lastLogAt: Long, now: Long): Boolean {
        if (stalls <= FIRST_LINES) return true
        return lastLogAt <= 0L || now - lastLogAt >= EVERY_MS || now < lastLogAt
    }
}

/**
 * Bundle 224 (C1): Add contact just after a Wi-Fi Direct group formed failed at
 * once with "not visible yet" because the other phone's beacon had not come.
 * The send now waits up to [WAIT_MS] for it, checking every [STEP_MS].
 * After a give-up the next sends to that phone fail fast for
 * [FAST_FAIL_AFTER_GIVE_UP_MS] (the app already retries 4 times).
 */
object PairEndpointWait {
    const val WAIT_MS = 10_000L
    const val STEP_MS = 500L
    const val FAST_FAIL_AFTER_GIVE_UP_MS = 30_000L

    enum class Step { SEND, WAIT, GIVE_UP }

    fun next(elapsedMs: Long, found: Boolean): Step = when {
        found -> Step.SEND
        elapsedMs >= WAIT_MS -> Step.GIVE_UP
        else -> Step.WAIT
    }

    fun mayWait(lastGiveUpAt: Long, now: Long): Boolean =
        lastGiveUpAt <= 0L || now < lastGiveUpAt || now - lastGiveUpAt >= FAST_FAIL_AFTER_GIVE_UP_MS
}

