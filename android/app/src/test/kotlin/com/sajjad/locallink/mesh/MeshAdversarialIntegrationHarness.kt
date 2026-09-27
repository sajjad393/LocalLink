package com.sajjad.locallink.mesh

import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Deterministic, Android-free adversarial integration harness for PHASE 62.
 *
 * This is intentionally a main()-driven harness so it can be executed in the
 * repository even when Android SDK/Gradle/Flutter are unavailable.
 */
object MeshAdversarialIntegrationHarness {
    @JvmStatic
    fun main(args: Array<String>) {
        val checks = listOf(
            "route-control-flood" to ::routeControlFlood,
            "route-poisoning" to ::routePoisoning,
            "route-flapping" to ::routeFlapping,
            "route-table-exhaustion" to ::routeTableExhaustion,
            "duplicate-cache-exhaustion" to ::duplicateCacheExhaustion,
            "packet-replay-window" to ::packetReplayWindow,
            "session-key-rotation" to ::sessionKeyRotation,
            "multi-hop-resource-pressure" to ::multiHopResourcePressure,
        )
        checks.forEach { (name, check) ->
            try {
                check()
                println("PASS $name")
            } catch (error: Throwable) {
                System.err.println("FAIL $name: ${error.message}")
                throw error
            }
        }
        println("PHASE 62 adversarial integration harness: PASS (${checks.size} scenarios)")
    }

    private fun routeControlFlood() {
        val policy = MeshRouteAdvertisementPolicy()
        var accepted = 0
        var rejected = 0
        val now = 1_000_000L
        for (sequence in 1L..500L) {
            val decision = policy.evaluate("MAL", "session-main", sequence, now, 1, now)
            if (decision.accepted) accepted++ else rejected++
        }
        check(accepted == MeshLimits.MAX_ROUTE_ADVERTISEMENTS_PER_PEER) { "accepted=$accepted" }
        check(rejected == 500 - accepted) { "rejected=$rejected" }

        // A second peer must still be able to advertise: limits are per peer.
        check(policy.evaluate("GOOD", "session-good", 1L, now, 1, now).accepted)
    }

    private fun routePoisoning() {
        val policy = MeshRouteAdvertisementPolicy(maxRoutesPerAdvertisement = 4)
        val now = 2_000_000L
        check(policy.evaluate("B", "session-b", 1L, now, 4, now).accepted)
        check(policy.evaluate("B", "session-b", 2L, now, 5, now).reason == "route_count_exceeded")
        check(policy.evaluate("B", "session-b", 3L, now - MeshLimits.ROUTE_ADVERTISEMENT_MAX_AGE_MS - 1L, 1, now).reason == "stale_advertisement")
        check(policy.evaluate("B", "session-b", 4L, now + MeshLimits.ROUTE_ADVERTISEMENT_FUTURE_SKEW_MS + 1L, 1, now).reason == "future_advertisement")
    }

    private fun routeFlapping() {
        val policy = MeshRouteStabilityPolicy(
            flapWindowMs = 10_000L,
            maxChangesBeforeHoldDown = 3,
            holdDownMs = 2_000L,
        )
        fun route(next: String, expiry: Long = Long.MAX_VALUE): MeshRoute =
            MeshRoute("D", next, 2, expiry, 10_000L, 100L, listOf("A", next, "D"))
        check(policy.beforeChange("D", route("B"), route("C"), 10_000L).accepted)
        policy.recordAcceptedChange("D", "B", "C", 10_000L)
        policy.recordAcceptedChange("D", "C", "B", 10_100L)
        policy.recordAcceptedChange("D", "B", "C", 10_200L)
        check(!policy.beforeChange("D", route("C"), route("B"), 10_300L).accepted)
        check(policy.beforeChange("D", route("C"), route("B"), 12_300L).accepted)
    }

    private fun routeTableExhaustion() {
        val table = MeshRouteTable { "A" }
        var accepted = 0
        var rejected = 0
        for (i in 0 until (MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS + 32)) {
            val destination = "D$i"
            val route = MeshRoute(
                destinationNodeId = destination,
                nextHopNodeId = "N$i",
                hopCount = 2,
                expiresAt = Long.MAX_VALUE,
                lastSeenAt = 1_000L + i,
                routeVersion = 1_000L + i,
                path = listOf("A", "N$i", destination),
            )
            if (table.upsert(destination, route)) accepted++ else rejected++
        }
        check(accepted == MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS) { "accepted=$accepted" }
        check(rejected == 32) { "rejected=$rejected" }
        check(table.keys.size <= MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS)

        // Per-destination quota: the fifth candidate must not displace a stronger route.
        val bounded = MeshRouteTable { "A" }
        for (hopCount in 2..8) {
            val next = "N$hopCount"
            val middle = (1 until hopCount - 1).map { "X${hopCount}_$it" }
            val routePath = listOf("A", next) + middle + listOf("Z")
            val route = MeshRoute(
                destinationNodeId = "Z",
                nextHopNodeId = next,
                hopCount = hopCount,
                expiresAt = Long.MAX_VALUE,
                lastSeenAt = 2_000L + hopCount,
                routeVersion = 2_000L + hopCount,
                path = routePath,
            )
            bounded.upsert("Z", route)
        }
        check(bounded.allFor("Z").size == MeshLimits.MAX_ROUTES_PER_DESTINATION)
        check(bounded.allFor("Z").maxOf { it.hopCount } == MeshLimits.MAX_ROUTES_PER_DESTINATION + 1)

        val perHop = MeshRouteTable { "A" }
        var perHopAccepted = 0
        for (i in 0..MeshLimits.MAX_ROUTES_PER_NEXT_HOP) {
            val destination = "Q$i"
            val route = MeshRoute(destination, "SHARED", 2, Long.MAX_VALUE, 10_000L + i, 10_000L + i, listOf("A", "SHARED", destination))
            if (perHop.upsert(destination, route)) perHopAccepted++
        }
        check(perHopAccepted == MeshLimits.MAX_ROUTES_PER_NEXT_HOP) { "perHopAccepted=$perHopAccepted" }
    }

    private fun duplicateCacheExhaustion() {
        var evicted = 0
        val tracker = MeshSeenPacketTracker(
            maxEntries = 128,
            retentionMs = 60_000L,
            onEvicted = { _, _ -> evicted++ },
        )
        for (i in 0 until 2_000) {
            check(tracker.markSeen("SRC${i % 4}", "PKT$i", 5_000L + i))
        }
        check(tracker.size() <= 128) { "size=${tracker.size()}" }
        check(evicted > 0) { "no eviction occurred" }
        check(tracker.markSeen("SRC0", "PKT100", 7_500L)) { "oldest packet should be reaccepted after cache eviction" }
        check(!tracker.markSeen("SRC3", "PKT1999", 7_500L)) { "newest packet should still be protected from replay" }
    }

    private fun packetReplayWindow() {
        val tracker = MeshSeenPacketTracker(maxEntries = 16, retentionMs = 1_000L)
        check(tracker.restore("A", "p1", 10_000L, 10_500L))
        check(!tracker.restore("A", "p1", 10_000L, 10_500L))
        check(!tracker.restore("A", "future", 10_600L, 10_500L))
        check(!tracker.restore("A", "stale", 9_000L, 10_500L))
        tracker.cleanup(11_501L)
        check(tracker.size() == 0)
    }

    private fun sessionKeyRotation() {
        val shared = "shared-secret-for-test"
        val oldEpoch = 20L
        val newEpoch = 21L
        val oldKey = MeshTransportSessionKeyPolicy.deriveKey(shared, "A", "B", oldEpoch)
        val newKey = MeshTransportSessionKeyPolicy.deriveKey(shared, "A", "B", newEpoch)
        check(!oldKey.contentEquals(newKey))

        val plaintext = "active-call-sequence-42".toByteArray(StandardCharsets.UTF_8)
        val aadOld = "A|B|$oldEpoch".toByteArray(StandardCharsets.UTF_8)
        val encoded = encrypt(oldKey, plaintext, aadOld)
        check(decrypt(encoded, oldKey, aadOld).contentEquals(plaintext))
        check(runCatching { decrypt(encoded, newKey, aadOld) }.isFailure)

        val rotationNow = MeshTransportSessionKeyPolicy.ROTATION_MS * newEpoch + 1L
        val accepted = MeshTransportSessionKeyPolicy.acceptedEpochs(rotationNow)
        check(oldEpoch in accepted) { "previous epoch missing grace" }
        check(newEpoch in accepted) { "current epoch missing" }
        check(newEpoch + 1L in accepted) { "next epoch missing receive grace" }
    }

    private fun multiHopResourcePressure() {
        // Simulate 64 nodes each submitting control traffic and routes into one relay.
        val adPolicy = MeshRouteAdvertisementPolicy()
        val table = MeshRouteTable { "R" }
        val now = 9_000_000L
        var adAccepted = 0
        for (node in 0 until 64) {
            val peer = "P$node"
            for (seq in 1L..60L) {
                if (adPolicy.evaluate(peer, "session-$node", seq, now, 1, now).accepted) adAccepted++
            }
            val route = MeshRoute("D$node", peer, 2, Long.MAX_VALUE, now, 1L, listOf("R", peer, "D$node"))
            table.upsert("D$node", route)
        }
        check(adAccepted == 64 * MeshLimits.MAX_ROUTE_ADVERTISEMENTS_PER_PEER)
        check(table.keys.size <= MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS)
    }

    private fun encrypt(key: ByteArray, plaintext: ByteArray, aad: ByteArray): ByteArray {
        val iv = ByteArray(12).also(SecureRandom()::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
        cipher.updateAAD(aad)
        return iv + cipher.doFinal(plaintext)
    }

    private fun decrypt(encoded: ByteArray, key: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, encoded.copyOfRange(0, 12)))
        cipher.updateAAD(aad)
        return cipher.doFinal(encoded.copyOfRange(12, encoded.size))
    }
}
