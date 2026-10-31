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
