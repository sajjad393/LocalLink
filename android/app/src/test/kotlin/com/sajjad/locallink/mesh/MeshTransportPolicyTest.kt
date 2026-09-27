package com.sajjad.locallink.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshTransportPolicyTest {
    @Test fun `transport ports are canonical and valid`() {
        assertTrue(MeshTransportPolicy.isValidPort(MeshTransportPolicy.WIFI_DIRECT_PORT))
        assertTrue(MeshTransportPolicy.isValidPort(MeshTransportPolicy.LAN_PORT))
        assertTrue(MeshTransportPolicy.isValidPort(MeshTransportPolicy.LAN_DISCOVERY_PORT))
        assertFalse(MeshTransportPolicy.isValidPort(0))
        assertFalse(MeshTransportPolicy.isValidPort(65_536))
    }

    @Test fun `lan is preferred when a peer has both links`() {
        assertTrue(MeshTransportPolicy.shouldReplaceExistingTransport(
            MeshTransportPolicy.WIFI_DIRECT,
            MeshTransportPolicy.LAN,
        ))
        assertFalse(MeshTransportPolicy.shouldReplaceExistingTransport(
            MeshTransportPolicy.LAN,
            MeshTransportPolicy.WIFI_DIRECT,
        ))
    }

    @Test fun `same transport can refresh the peer connection`() {
        assertTrue(MeshTransportPolicy.shouldReplaceExistingTransport(
            MeshTransportPolicy.LAN,
            MeshTransportPolicy.LAN,
        ))
        assertTrue(MeshTransportPolicy.shouldReplaceExistingTransport(
            MeshTransportPolicy.WIFI_DIRECT,
            MeshTransportPolicy.WIFI_DIRECT,
        ))
    }
}
