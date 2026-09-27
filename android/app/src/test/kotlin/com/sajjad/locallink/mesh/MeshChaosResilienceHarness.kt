package com.sajjad.locallink.mesh

import com.sajjad.locallink.DirectFileTransferPolicy
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Deterministic chaos scenarios for resource exhaustion, churn, partition and restart recovery. */
object MeshChaosResilienceHarness {
    private val NOW: Long = System.currentTimeMillis()

    @JvmStatic
    fun main(args: Array<String>) = runAll()

    fun runAll() {
        run("route_table_destination_flood") { routeTableDestinationFlood() }
        run("route_table_next_hop_flood") { routeTableNextHopFlood() }
        run("recovery_tracker_flood") { recoveryTrackerFlood() }
        run("duplicate_cache_exhaustion") { duplicateCacheExhaustion() }
        run("route_flap_hold_down") { routeFlapHoldDown() }
        run("route_partition_alternate_recovery") { routePartitionAlternateRecovery() }
        run("route_advertisement_replay_and_rate_limit") { routeAdvertisementReplayAndRateLimit() }
        run("session_key_rotation") { sessionKeyRotation() }
        run("direct_file_resource_bounds") { directFileResourceBounds() }
        run("concurrent_route_and_replay_stress") { concurrentRouteAndReplayStress() }
        println("PHASE 66 CHAOS HARNESS: 10/10 PASS")
    }

    private fun run(name: String, block: () -> Unit) {
        try {
            block()
            println("PASS $name")
        } catch (t: Throwable) {
            System.err.println("FAIL $name: ${t.message}")
            throw t
        }
    }

    private fun require(condition: Boolean, message: String) {
        check(condition) { message }
    }

    private fun routeTable(): MeshRouteTable = MeshRouteTable { "A" }

    private fun route(destination: String, nextHop: String, hops: Int, version: Long, base: Long = NOW): MeshRoute =
        MeshRoute(
            destinationNodeId = destination,
            nextHopNodeId = nextHop,
            hopCount = hops,
            expiresAt = base + 600_000L,
            lastSeenAt = base,
            routeVersion = version,
            path = when (hops) {
                1 -> listOf("A", destination)
                2 -> listOf("A", nextHop, destination)
                else -> (listOf("A", nextHop) + (1 until hops).map { "X$it" } + destination).take(hops + 1)
            },
        )

    private fun routeTableDestinationFlood() {
        val table = routeTable()
        var accepted = 0
        for (i in 0 until 5_000) {
            if (table.upsert("D$i", route("D$i", "B$i", 2, i.toLong() + 1L))) accepted++
        }
        require(accepted == MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS, "destination cap not enforced: $accepted")
        require(table.keys.size == MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS, "route table exceeded destination cap")
    }

    private fun routeTableNextHopFlood() {
        val table = routeTable()
        var accepted = 0
        for (i in 0 until 200) {
            if (table.upsert("D$i", route("D$i", "B", 2, i.toLong() + 1L))) accepted++
        }
        require(accepted == MeshLimits.MAX_ROUTES_PER_NEXT_HOP, "next-hop cap not enforced: $accepted")
        require(table.all().values.flatten().all { it.nextHopNodeId == "B" }, "unexpected next hop")
    }

    private fun recoveryTrackerFlood() {
        val tracker = MeshRouteRecoveryTracker(retentionMs = 60_000L)
        val affected = tracker.markPeerLost("B", (0 until 10_000).map { "D$it" }, NOW)
        require(affected.size == MeshLimits.MAX_ROUTE_RECOVERY_DESTINATIONS, "recovery return was not bounded")
        require(tracker.size() == MeshLimits.MAX_ROUTE_RECOVERY_DESTINATIONS, "recovery state exceeded cap")
        require(tracker.pendingForPeer("B").size == MeshLimits.MAX_ROUTE_RECOVERY_DESTINATIONS, "recovery snapshot exceeded cap")
        tracker.prune(NOW + 60_000L)
        require(tracker.size() == 0, "expired recovery state was retained")
    }

    private fun duplicateCacheExhaustion() {
        val tracker = MeshSeenPacketTracker(maxEntries = 8192, retentionMs = 120_000L)
        for (i in 0 until 20_000) {
            tracker.markSeen("S$i", "P$i", NOW)
        }
        require(tracker.size() == 8192, "duplicate cache cap failed: ${tracker.size()}")
        require(!tracker.markSeen("S19999", "P19999", NOW), "duplicate packet was accepted twice")
        tracker.cleanup(NOW + 120_001L)
        require(tracker.size() == 0, "duplicate cache expiry failed")
    }

    private fun routeFlapHoldDown() {
        val policy = MeshRouteStabilityPolicy(
            flapWindowMs = 30_000L,
            maxChangesBeforeHoldDown = 3,
            holdDownMs = 15_000L,
            staleGraceMs = 5_000L,
        )
        var current = route("D", "B", 2, 1)
        var now = NOW
        repeat(3) { index ->
            val nextHop = if (index % 2 == 0) "C" else "B"
            val candidate = route("D", nextHop, 2, 10 + index.toLong())
            val decision = policy.beforeChange("D", current, candidate, now)
            require(decision.accepted, "change $index unexpectedly blocked")
            policy.recordAcceptedChange("D", current.nextHopNodeId, candidate.nextHopNodeId, now)
            current = candidate
            now += 1_000L
        }
        val blocked = policy.beforeChange("D", current, route("D", "B", 2, 20), now)
        require(!blocked.accepted && blocked.reason == "route_hold_down", "route flap hold-down failed: $blocked")
        require(policy.beforeChange("D", current, route("D", "B", 2, 21), now + 15_001L).accepted, "hold-down did not expire")
    }

    private fun routePartitionAlternateRecovery() {
        val table = routeTable()
        table.upsert("D", route("D", "B", 2, 11))
        table.upsert("D", route("D", "C", 2, 10))
        require(table.bestRoute("D")?.nextHopNodeId == "B", "best route selection wrong")
        table.markRecoveringVia("B")
        require(table.bestRoute("D")?.nextHopNodeId == "C", "alternate route did not survive partition")
        val tracker = MeshRouteRecoveryTracker()
        tracker.markPeerLost("B", listOf("D"), NOW)
        tracker.markRecovered("D")
        require(tracker.size() == 0, "recovery state not cleared after alternate recovery")
    }

    private fun routeAdvertisementReplayAndRateLimit() {
        val policy = MeshRouteAdvertisementPolicy()
        val first = policy.evaluate("B", "session-0001", 1, NOW, 3, NOW)
        require(first.accepted, "first advertisement rejected")
        val replay = policy.evaluate("B", "session-0001", 1, NOW, 3, NOW)
        require(!replay.accepted && replay.reason == "replay_or_out_of_order", "replay protection failed")
        for (sequence in 2..MeshLimits.MAX_ROUTE_ADVERTISEMENTS_PER_PEER) {
            require(policy.evaluate("B", "session-0001", sequence.toLong(), NOW, 1, NOW).accepted, "rate window rejected valid advertisement $sequence")
        }
        val limited = policy.evaluate("B", "session-0001", 31, NOW, 1, NOW)
        require(!limited.accepted && limited.reason == "rate_limited", "advertisement rate limit failed")
        val oldSession = policy.evaluate("B", "session-0001", 99, NOW, 1, NOW + MeshLimits.ROUTE_ADVERTISEMENT_MAX_AGE_MS + 1L)
        require(!oldSession.accepted || oldSession.reason != "accepted", "stale session replay was accepted")
    }

    private fun sessionKeyRotation() {
        val epoch = MeshTransportSessionKeyPolicy.currentEpoch(NOW)
        val current = MeshTransportSessionKeyPolicy.deriveKey("shared", "A", "B", epoch)
        val next = MeshTransportSessionKeyPolicy.deriveKey("shared", "A", "B", epoch + 1)
        val reverse = MeshTransportSessionKeyPolicy.deriveKey("shared", "B", "A", epoch)
        require(!current.contentEquals(next), "session key did not rotate")
        require(!current.contentEquals(reverse), "directional session binding failed")
        require(MeshTransportSessionKeyPolicy.acceptedEpochs(NOW).contains(epoch - 1), "previous epoch grace missing")
        require(MeshTransportSessionKeyPolicy.acceptedEpochs(NOW).contains(epoch), "current epoch missing")
    }

    private fun directFileResourceBounds() {
        require(DirectFileTransferPolicy.expectedChunks(0) == 1, "zero-size transfer chunk invariant failed")
        require(DirectFileTransferPolicy.expectedChunks(DirectFileTransferPolicy.CHUNK_SIZE.toLong()) == 1, "exact chunk boundary failed")
        require(DirectFileTransferPolicy.expectedChunks(DirectFileTransferPolicy.CHUNK_SIZE.toLong() + 1) == 2, "chunk rollover failed")
        require(DirectFileTransferPolicy.validTransferSize(DirectFileTransferPolicy.MAX_DIRECT_FILE_SIZE), "maximum file size rejected")
        require(!DirectFileTransferPolicy.validTransferSize(DirectFileTransferPolicy.MAX_DIRECT_FILE_SIZE + 1), "oversize file accepted")
        require(DirectFileTransferPolicy.activeBytes(listOf(1, 2, 3)) == 6L, "active byte accounting failed")
        require(DirectFileTransferPolicy.activeBytes(listOf(-1, 2)) == 2L, "negative byte normalization failed")
    }

    private fun concurrentRouteAndReplayStress() {
        val table = routeTable()
        val seen = MeshSeenPacketTracker(maxEntries = 8192, retentionMs = 120_000L)
        val errors = ConcurrentLinkedQueue<Throwable>()
        val pool = Executors.newFixedThreadPool(12)
        val start = CountDownLatch(1)
        val done = CountDownLatch(12)
        repeat(12) { worker ->
            pool.execute {
                try {
                    start.await()
                    repeat(1_000) { i ->
                        val d = "C${worker}_$i"
                        table.upsert(d, route(d, "N$worker", 2, i + 1L))
                        seen.markSeen("S$worker", "P${worker}_$i", NOW)
                    }
                } catch (t: Throwable) {
                    errors += t
                } finally {
                    done.countDown()
                }
            }
        }
        start.countDown()
        require(done.await(20, TimeUnit.SECONDS), "concurrent chaos workers timed out")
        pool.shutdownNow()
        require(errors.isEmpty(), "concurrent mesh state threw ${errors.peek()}")
        require(table.keys.size <= MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS, "route table exceeded cap under concurrency")
        require(table.all().values.flatten().size <= MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS * MeshLimits.MAX_ROUTES_PER_DESTINATION, "route entry bound exceeded under concurrency")
        require(seen.size() <= MeshLimits.MAX_SEEN_PACKETS, "duplicate cache exceeded cap under concurrency")
    }
}
