package com.sajjad.locallink.mesh

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshRouteAdvertisementAuthenticatorTest {
    @Test
    fun signatureVerifiesAndDetectsRouteTampering() {
        val key = "shared-secret"
        val unsigned = JSONObject()
            .put("type", "route_advertisement")
            .put("route_protocol_version", 2)
            .put("sender_id", "B")
            .put("session_id", "session-1")
            .put("advertisement_sequence", 7L)
            .put("sent_at", 1_000L)
            .put("routes", JSONArray().put(JSONObject().put("destination_node_id", "D").put("hop_count", 2).put("route_version", 900L).put("path", JSONArray().put("B").put("C").put("D"))))
        val signed = MeshRouteAdvertisementAuthenticator.withAuth(unsigned, key)
        assertTrue(MeshRouteAdvertisementAuthenticator.verify(signed, key))
        assertFalse(MeshRouteAdvertisementAuthenticator.verify(signed.put("route_version_tamper", 1), key))
        signed.getJSONArray("routes").getJSONObject(0).put("hop_count", 1)
        assertFalse(MeshRouteAdvertisementAuthenticator.verify(signed, key))
    }

    @Test
    fun wrongKeyAndMissingAuthAreRejected() {
        val advertisement = JSONObject()
            .put("type", "route_advertisement")
            .put("route_protocol_version", 2)
            .put("sender_id", "B")
            .put("session_id", "session-1")
            .put("advertisement_sequence", 1L)
            .put("sent_at", 1_000L)
            .put("routes", JSONArray())
        assertFalse(MeshRouteAdvertisementAuthenticator.verify(advertisement, "shared"))
        val signed = MeshRouteAdvertisementAuthenticator.withAuth(advertisement, "shared")
        assertFalse(MeshRouteAdvertisementAuthenticator.verify(signed, "wrong"))
    }
    @Test
    fun routeWithdrawalUsesTheSameAuthenticatedControlEnvelope() {
        val message = JSONObject()
            .put("type", "route_withdrawal")
            .put("sender_id", "B")
            .put("session_id", "session-1")
            .put("control_sequence", 8L)
            .put("sent_at", 1_000L)
            .put("failed_next_hop", "B")
            .put("destinations", JSONArray().put("D"))
        val signed = MeshRouteAdvertisementAuthenticator.withAuth(message, "shared")
        assertTrue(MeshRouteAdvertisementAuthenticator.verify(signed, "shared"))
        signed.put("destinations", JSONArray().put("E"))
        assertFalse(MeshRouteAdvertisementAuthenticator.verify(signed, "shared"))
    }

}
