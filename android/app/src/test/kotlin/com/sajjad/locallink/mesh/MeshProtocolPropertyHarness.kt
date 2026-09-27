package com.sajjad.locallink.mesh

import java.util.Random
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Deterministic JDK-only property/fuzz harness for dependency-free mesh security policies.
 * Android's org.json codec is exercised separately by MeshPacketFuzzTest.
 */
object MeshProtocolPropertyHarness {
    private const val SEED = 0x6c6f63616c6c696eL
    private const val ITERATIONS = 20_000
    private const val MAX_REASON_LENGTH = 64

    @JvmStatic
    fun main(args: Array<String>) {
        val rng = Random(SEED)
        run("identifier-properties") { fuzzIdentifiers(rng) }
        run("route-table-properties") { fuzzRouteTable(rng) }
        run("route-advertisement-properties") { fuzzRouteAdvertisements(rng) }
        run("replay-cache-properties") { fuzzReplayTracker(rng) }
        run("recovery-properties") { fuzzRecoveryTracker(rng) }
        run("route-stability-properties") { fuzzRouteStability(rng) }
        run("session-key-properties") { fuzzSessionKeys(rng) }
        run("encrypted-boundary-properties") { fuzzEncryptedBoundaries(rng) }
        run("concurrent-state-properties") { fuzzConcurrentState() }
        println("PHASE 67 JDK PROPERTY HARNESS: PASS (9 scenarios, seed=$SEED, iterations=$ITERATIONS)")
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

    private fun fuzzIdentifiers(rng: Random) {
        repeat(ITERATIONS) {
            val candidate = randomString(rng, rng.nextInt(160))
            val valid = MeshIdPolicy.isValid(candidate)
            if (valid) check(candidate.trim().isNotEmpty() && candidate.trim().length <= MeshIdPolicy.MAX_ID_LENGTH)
            val type = randomString(rng, rng.nextInt(160))
            val typeValid = MeshIdPolicy.isValidType(type)
            if (typeValid) check(type.trim().isNotEmpty() && type.trim().length <= MeshIdPolicy.MAX_TYPE_LENGTH)
        }
    }

    private fun fuzzRouteTable(rng: Random) {
        val table = MeshRouteTable { "A" }
        repeat(ITERATIONS) { i ->
            val destination = "D${rng.nextInt(700)}"
            val next = "N${rng.nextInt(100)}"
            val hops = 1 + rng.nextInt(MeshLimits.MAX_HOPS)
            val path = buildPath(next, destination, hops)
            val route = MeshRoute(
                destinationNodeId = destination,
                nextHopNodeId = next,
                hopCount = hops,
                expiresAt = 5_000_000L,
                lastSeenAt = 4_000_000L + (i % 10_000),
                routeVersion = (i + 1).toLong(),
                path = path,
            )
            table.upsert(destination, route)
            check(table.keys.size <= MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS)
            check(table.all().values.sumOf { it.size } <=
                MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS * MeshLimits.MAX_ROUTES_PER_DESTINATION)
        }
        table.all().values.flatten().forEach { route ->
            check(route.path.size == route.hopCount + 1)
            check(route.path.first() == "A")
            check(route.path.last() == route.destinationNodeId)
            check(route.path.distinct().size == route.path.size)
        }
    }

    private fun fuzzRouteAdvertisements(rng: Random) {
        val policy = MeshRouteAdvertisementPolicy()
        val allowedReasons = setOf(
            "accepted",
            "invalid_sender",
            "invalid_session",
            "invalid_sequence",
            "route_count_exceeded",
            "invalid_timestamp",
            "stale_advertisement",
            "future_advertisement",
            "rate_limited",
            "replay_or_out_of_order",
            "old_session_replay",
        )
        val base = 10_000_000L
        repeat(ITERATIONS) { i ->
            val now = base + i
            val sentAt = when (rng.nextInt(8)) {
                0 -> 0L
                1 -> now - MeshLimits.ROUTE_ADVERTISEMENT_MAX_AGE_MS - 1L
                2 -> now + MeshLimits.ROUTE_ADVERTISEMENT_FUTURE_SKEW_MS + 1L
                else -> now - rng.nextInt(10_000)
            }
            val decision = policy.evaluate(
                peerId = "P${rng.nextInt(32)}",
                sessionId = "session-${rng.nextInt(8)}",
                sequence = rng.nextLong().let { if (it == Long.MIN_VALUE) 1L else kotlin.math.abs(it) },
                sentAt = sentAt,
                routeCount = rng.nextInt(200),
                now = now,
            )
            check(decision.reason in allowedReasons) { "unexpected reason ${decision.reason}" }
            check(decision.reason.length <= MAX_REASON_LENGTH)
        }
    }

    private fun fuzzReplayTracker(rng: Random) {
        val tracker = MeshSeenPacketTracker(maxEntries = 256, retentionMs = 60_000L, cleanupIntervalMs = 500L)
        val start = 20_000_000L
        repeat(ITERATIONS) { i ->
            val now = start + i
            val source = "S${rng.nextInt(64)}"
            val packet = "P${rng.nextInt(512)}"
            tracker.markSeen(source, packet, now)
            if (i % 31 == 0) tracker.cleanup(now)
            check(tracker.size() <= 256)
        }
        tracker.cleanup(start + ITERATIONS.toLong() + 61_000L)
        check(tracker.size() == 0)
    }

    private fun fuzzRecoveryTracker(rng: Random) {
        val tracker = MeshRouteRecoveryTracker(retentionMs = 30_000L)
        val now = 30_000_000L
        repeat(ITERATIONS) {
            val destinations = List(rng.nextInt(40)) { "D${rng.nextInt(1000)}" }
            tracker.markPeerLost("B", destinations, now)
            check(tracker.size() <= MeshLimits.MAX_ROUTE_RECOVERY_DESTINATIONS)
            check(tracker.pendingForPeer("B").size <= MeshLimits.MAX_ROUTE_RECOVERY_DESTINATIONS)
        }
        tracker.prune(now + 30_001L)
        check(tracker.size() == 0)
    }

    private fun fuzzRouteStability(rng: Random) {
        val policy = MeshRouteStabilityPolicy()
        val now = 40_000_000L
        var currentHop = "B"
        repeat(ITERATIONS) { i ->
            val candidateHop = if (rng.nextBoolean()) "B" else "C"
            val current = simpleRoute(currentHop, now + 60_000L, i + 1L)
            val candidate = simpleRoute(candidateHop, now + 60_000L, i + 2L)
            val decision = policy.beforeChange("D", current, candidate, now + i)
            check(decision.reason.length <= MAX_REASON_LENGTH)
            if (decision.accepted && currentHop != candidateHop) {
                policy.recordAcceptedChange("D", currentHop, candidateHop, now + i)
                currentHop = candidateHop
            }
        }
    }

    private fun fuzzSessionKeys(rng: Random) {
        repeat(ITERATIONS) {
            val shared = "shared-${rng.nextInt(64)}"
            val epoch = rng.nextInt(10_000).toLong()
            val a = MeshTransportSessionKeyPolicy.deriveKey(shared, "A", "B", epoch)
            val b = MeshTransportSessionKeyPolicy.deriveKey(shared, "A", "B", epoch)
            check(a.contentEquals(b))
            check(!a.contentEquals(MeshTransportSessionKeyPolicy.deriveKey(shared, "A", "B", epoch + 1L)))
            check(!a.contentEquals(MeshTransportSessionKeyPolicy.deriveKey(shared, "B", "A", epoch)))
        }
    }

    private fun fuzzEncryptedBoundaries(rng: Random) {
        repeat(4_000) {
            val key = ByteArray(32).also(rng::nextBytes)
            val plain = ByteArray(rng.nextInt(8_192)).also(rng::nextBytes)
            val aad = ByteArray(rng.nextInt(128)).also(rng::nextBytes)
            val encoded = encrypt(key, plain, aad, rng)
            check(decrypt(encoded, key, aad).contentEquals(plain))

            val tamperIndex = 12 + rng.nextInt(maxOf(1, encoded.size - 12))
            val tampered = encoded.copyOf().also { it[tamperIndex] = (it[tamperIndex].toInt() xor 0x01).toByte() }
            check(runCatching { decrypt(tampered, key, aad) }.isFailure)

            if (encoded.size > 13) {
                val truncated = encoded.copyOf(encoded.size - 1)
                check(runCatching { decrypt(truncated, key, aad) }.isFailure)
            }
        }
    }

    private fun fuzzConcurrentState() {
        val table = MeshRouteTable { "A" }
        val seen = MeshSeenPacketTracker(maxEntries = 2048, retentionMs = 60_000L)
        val pool = Executors.newFixedThreadPool(8)
        val start = CountDownLatch(1)
        val done = CountDownLatch(8)
        val errors = mutableListOf<Throwable>()
        repeat(8) { worker ->
            pool.execute {
                try {
                    start.await()
                    repeat(3_000) { i ->
                        val d = "D${worker}_$i"
                        table.upsert(d, simpleRoute("N$worker", 99_000_000L, i.toLong() + 1L, d))
                        seen.markSeen("S$worker", "P$i", 99_000_000L + i)
                    }
                } catch (t: Throwable) {
                    synchronized(errors) { errors += t }
                } finally {
                    done.countDown()
                }
            }
        }
        start.countDown()
        check(done.await(20, java.util.concurrent.TimeUnit.SECONDS))
        pool.shutdownNow()
        check(errors.isEmpty()) { "concurrent error: ${errors.firstOrNull()}" }
        check(table.keys.size <= MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS)
        check(seen.size() <= 2_048)
    }

    private fun simpleRoute(nextHop: String, expiry: Long, version: Long, destination: String = "D"): MeshRoute =
        MeshRoute(destination, nextHop, 2, expiry, expiry - 60_000L, version, listOf("A", nextHop, destination))

    private fun buildPath(nextHop: String, destination: String, hops: Int): List<String> {
        if (hops == 1) return listOf("A", destination)
        val middle = (1 until hops - 1).map { "X$it" }
        return listOf("A", nextHop) + middle + destination
    }

    private fun randomString(rng: Random, length: Int): String {
        val alphabet = "abcXYZ0123_ -|\u0000\u0001\n"
        return buildString(length) {
            repeat(length) { append(alphabet[rng.nextInt(alphabet.length)]) }
        }
    }

    private fun encrypt(key: ByteArray, plaintext: ByteArray, aad: ByteArray, rng: Random): ByteArray {
        val iv = ByteArray(12).also(rng::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
        cipher.updateAAD(aad)
        return iv + cipher.doFinal(plaintext)
    }

    private fun decrypt(encoded: ByteArray, key: ByteArray, aad: ByteArray): ByteArray {
        require(encoded.size >= 28) { "ciphertext too short" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, encoded.copyOfRange(0, 12)))
        cipher.updateAAD(aad)
        return cipher.doFinal(encoded.copyOfRange(12, encoded.size))
    }
}
