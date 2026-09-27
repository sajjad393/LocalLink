package com.sajjad.locallink.mesh

/**
 * Shared transport-level constants and validation. Both LAN and Wi-Fi Direct
 * ultimately carry the same MeshPacket through MeshRouter.
 */
object MeshTransportPolicy {
    const val WIFI_DIRECT: String = "wifi_direct"
    const val LAN: String = "lan"

    const val WIFI_DIRECT_PORT: Int = 8988
    const val LAN_PORT: Int = 8989
    const val LAN_DISCOVERY_PORT: Int = 8990

    const val DISCOVERY_PROTOCOL_VERSION: Int = 1
    const val LAN_BEACON_INTERVAL_MS: Long = 3_000L
    const val LAN_ENDPOINT_RETENTION_MS: Long = 12_000L
    const val SOCKET_CONNECT_TIMEOUT_MS: Int = 3_000
    const val HEARTBEAT_INTERVAL_MS: Long = 5_000L
    const val HEARTBEAT_TIMEOUT_MS: Long = 15_000L

    /** One logical active link is kept per peer; LAN is preferred when both links exist. */
    fun transportPriority(name: String): Int = when (name) {
        LAN -> 20
        WIFI_DIRECT -> 10
        else -> 0
    }

    fun isSupportedTransport(name: String): Boolean =
        name == LAN || name == WIFI_DIRECT

    fun isValidPort(port: Int): Boolean = port in 1..65_535

    fun shouldReplaceExistingTransport(existing: String, incoming: String): Boolean {
        if (existing == incoming) return true
        return transportPriority(incoming) > transportPriority(existing)
    }
}
