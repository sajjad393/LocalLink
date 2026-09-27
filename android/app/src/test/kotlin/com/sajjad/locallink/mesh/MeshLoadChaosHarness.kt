package com.sajjad.locallink.mesh

import com.sajjad.locallink.DirectFileTransferPolicy
import java.util.Random
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.max

/**
 * Phase 68 deterministic load/chaos harness.
 *
 * It exercises the bounded, dependency-free mesh policies at materially higher
 * volume than Phase 66/67 and injects repeatable route/peer/replay churn.
 * Physical Android, LAN/Wi-Fi Direct, native mesh media and Flutter execution remain
 * outside this JVM-only harness.
 */
object MeshLoadChaosHarness {
    private const val SEED = 0x4c6f61644368616fL // "LoadChao"
    private const val LOAD_ITERATIONS = 120_000
    private const val CHAOS_STEPS = 80_000
    private const val WORKERS = 24
    private const val WORKER_ITERATIONS = 6_000

    @JvmStatic
    fun main(args: Array<String>) {
        val startedAt = System.nanoTime()
        run("high-volume-route-load") { highVolumeRouteLoad() }
        run("high-volume-replay-load") { highVolumeReplayLoad() }
        run("recovery-churn") { recoveryChurn() }
        run("deterministic-topology-chaos") { deterministicTopologyChaos() }
        run("concurrent-multi-peer-load") { concurrentMultiPeerLoad() }
        run("resource-boundary-soak") { resourceBoundarySoak() }
        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000L
        println("PHASE 68 JVM LOAD/CHAOS: 6/6 PASS elapsed_ms=$elapsedMs seed=$SEED")
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

    private fun highVolumeRouteLoad() {
        val rng = Random(SEED)
        val table = MeshRouteTable { "A" }
        repeat(LOAD_ITERATIONS) { i ->
            val destination = "D${rng.nextInt(900)}"
            val nextHop = "N${rng.nextInt(96)}"
            val hops = 1 + rng.nextInt(MeshLimits.MAX_HOPS)
            val route = route(destination, nextHop, hops, i + 1L, 10_000_000L + i)
            table.upsert(destination, route)
            check(table.keys.size <= MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS)
            check(table.all().values.sumOf { it.size } <=
                MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS * MeshLimits.MAX_ROUTES_PER_DESTINATION)
        }
        check(table.all().values.flatten().all { it.path.distinct().size == it.path.size })
    }

    private fun highVolumeReplayLoad() {
        val tracker = MeshSeenPacketTracker(
            maxEntries = MeshLimits.MAX_SEEN_PACKETS,
            retentionMs = MeshLimits.SEEN_RETENTION_MS,
            cleanupIntervalMs = 250L,
        )
        var duplicateHits = 0
        var now = 20_000_000L
        repeat(LOAD_ITERATIONS * 2) { i ->
            val source = "S${i % 16}"
            val packet = "P${i % 2_000}"
            if (!tracker.markSeen(source, packet, now)) duplicateHits++
            if (i % 503 == 0) now += 1_000L
            check(tracker.size() <= MeshLimits.MAX_SEEN_PACKETS)
        }
        check(duplicateHits > 0) { "replay workload did not exercise duplicate rejection" }
        tracker.cleanup(now + MeshLimits.SEEN_RETENTION_MS + 1L)
        check(tracker.size() == 0) { "replay entries survived expiry" }
    }

    private fun recoveryChurn() {
        val tracker = MeshRouteRecoveryTracker(retentionMs = 30_000L)
        var now = 30_000_000L
        repeat(LOAD_ITERATIONS / 2) { i ->
            val peer = "N${i % 64}"
            val destinations = List(1 + (i % 20)) { "D${(i * 31 + it) % 2_000}" }
            tracker.markPeerLost(peer, destinations, now)
            if (i % 211 == 0) tracker.markRecovered("D${(i * 7) % 2_000}")
            if (i % 997 == 0) tracker.prune(now - 1L)
            check(tracker.size() <= MeshLimits.MAX_ROUTE_RECOVERY_DESTINATIONS)
            now += 3L
        }
        tracker.prune(now + 30_001L)
        check(tracker.size() == 0)
    }

    private fun deterministicTopologyChaos() {
        val rng = Random(SEED xor 0x1234ABCDL)
        val table = MeshRouteTable { "A" }
        val seen = MeshSeenPacketTracker(maxEntries = 4_096, retentionMs = 120_000L)
        val stability = MeshRouteStabilityPolicy()
        var currentRoutes = mutableMapOf<String, MeshRoute>()
        var now = 40_000_000L

        repeat(CHAOS_STEPS) { step ->
            val destination = "D${rng.nextInt(128)}"
            val action = rng.nextInt(7)
            when (action) {
                0, 1 -> {
                    val nextHop = "N${rng.nextInt(16)}"
                    val candidate = route(destination, nextHop, 2 + rng.nextInt(3), step + 1L, now)
                    val current = currentRoutes[destination]
                    if (current == null) {
                        table.upsert(destination, candidate)
                        currentRoutes[destination] = table[destination] ?: candidate
                    } else {
                        val decision = stability.beforeChange(destination, current, candidate, now)
                        if (decision.accepted) {
                            table.upsert(destination, candidate)
                            stability.recordAcceptedChange(destination, current.nextHopNodeId, candidate.nextHopNodeId, now)
                            currentRoutes[destination] = candidate
                        }
                    }
                }
                2 -> {
                    table.markRecoveringVia("N${rng.nextInt(16)}")
                }
                3 -> {
                    table.prune(now + 1_000L) { true }
                }
                4 -> {
                    val source = "S${rng.nextInt(32)}"
                    val packet = "P${rng.nextInt(512)}"
                    seen.markSeen(source, packet, now)
                }
                5 -> {
                    val failed = "N${rng.nextInt(16)}"
                    table.all().forEach { (destination, routes) ->
                        if (routes.any { it.nextHopNodeId == failed }) table.remove(destination, failed)
                    }
                }
                else -> {
                    seen.cleanup(now)
                }
            }
            now += 17L
            check(table.keys.size <= MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS)
            check(seen.size() <= 4_096)
            check(currentRoutes.size <= MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS)
        }
    }

    private fun concurrentMultiPeerLoad() {
        val table = MeshRouteTable { "A" }
        val seen = MeshSeenPacketTracker(maxEntries = 8_192, retentionMs = 120_000L, cleanupIntervalMs = 500L)
        val errors = ConcurrentLinkedQueue<Throwable>()
        val pool = Executors.newFixedThreadPool(WORKERS)
        val start = CountDownLatch(1)
        val done = CountDownLatch(WORKERS)
        repeat(WORKERS) { worker ->
            pool.execute {
                try {
                    start.await()
                    val base = 60_000_000L + worker * 10_000L
                    repeat(WORKER_ITERATIONS) { i ->
                        val destination = "D${worker}_$i"
                        val nextHop = "N${worker % 32}"
                        table.upsert(destination, route(destination, nextHop, 2, i + 1L, base + i))
                        seen.markSeen("S$worker", "P$i", base + i)
                        if (i % 700 == 0) seen.cleanup(base + i)
                    }
                } catch (t: Throwable) {
                    errors += t
                } finally {
                    done.countDown()
                }
            }
        }
        start.countDown()
        check(done.await(45, TimeUnit.SECONDS)) { "concurrent load timed out" }
        pool.shutdownNow()
        check(errors.isEmpty()) { "concurrent load error: ${errors.firstOrNull()}" }
        check(table.keys.size <= MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS)
        check(seen.size() <= 8_192)
    }

    private fun resourceBoundarySoak() {
        val tracker = MeshSeenPacketTracker(maxEntries = 256, retentionMs = 5_000L, cleanupIntervalMs = 100L)
        val recovery = MeshRouteRecoveryTracker(retentionMs = 5_000L, maxEntries = 128)
        val rng = Random(SEED xor 0x55AA55AAL)
        var now = 90_000_000L
        repeat(CHAOS_STEPS) { i ->
            repeat(4) {
                tracker.markSeen("S${rng.nextInt(64)}", "P${rng.nextInt(4_000)}", now)
            }
            recovery.markPeerLost("N${rng.nextInt(32)}", List(rng.nextInt(32)) { "D${rng.nextInt(2_000)}" }, now)
            if (i % 500 == 0) {
                tracker.cleanup(now)
                recovery.prune(now)
            }
            check(tracker.size() <= 256)
            check(recovery.size() <= 128)
            now += max(1, rng.nextInt(40)).toLong()
        }
        check(DirectFileTransferPolicy.expectedChunks(0) == 1)
        check(DirectFileTransferPolicy.expectedChunks(DirectFileTransferPolicy.CHUNK_SIZE.toLong() + 1) == 2)
        check(!DirectFileTransferPolicy.validTransferSize(DirectFileTransferPolicy.MAX_DIRECT_FILE_SIZE + 1))
    }

    private fun route(destination: String, nextHop: String, hops: Int, version: Long, now: Long): MeshRoute {
        val boundedHops = hops.coerceIn(1, MeshLimits.MAX_HOPS)
        val middle = if (boundedHops <= 2) emptyList() else (1 until boundedHops - 1).map { "X${it}_$destination" }
        return MeshRoute(
            destinationNodeId = destination,
            nextHopNodeId = nextHop,
            hopCount = boundedHops,
            expiresAt = now + 600_000L,
            lastSeenAt = now,
            routeVersion = version,
            path = listOf("A", nextHop) + middle + destination,
        )
    }
}
