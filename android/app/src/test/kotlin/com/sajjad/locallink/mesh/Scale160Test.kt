package com.sajjad.locallink.mesh

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 160: scale to 300+ phones. */
class Scale160Test {
    private val now = System.currentTimeMillis()

    private fun adv(dest: String, hops: Int = 2, version: Long = 1L, via: String = "x") =
        MeshAdvertisedRoute(dest, hops, version, if (hops == 1) listOf("me", dest) else listOf("me", via, dest))

    // ------------------------------------------------ 160.1 changes only

    @Test fun `first diff sends everything then only what changed`() {
        val sender = MeshRouteDeltaSender()
        val first = sender.diff(listOf(adv("a"), adv("b")))
        assertEquals(listOf("a", "b"), first.changed.map { it.destination })
        assertTrue(first.withdrawn.isEmpty())
        val same = sender.diff(listOf(adv("a"), adv("b")))
        assertTrue(same.isEmpty)
        val changed = sender.diff(listOf(adv("a", hops = 3, version = 2L), adv("c")))
        assertEquals(listOf("a", "c"), changed.changed.map { it.destination })
        assertEquals(listOf("b"), changed.withdrawn)
    }

    @Test fun `a big change is split into parts of 128`() {
        val sender = MeshRouteDeltaSender()
        val routes = (0 until 300).map { adv("d$it") }
        val delta = sender.diff(routes)
        val chunks = sender.chunks(delta)
        assertEquals(3, chunks.size)
        assertTrue(chunks.all { it.changed.size <= 128 && it.withdrawn.size <= 128 })
        assertEquals(300, chunks.sumOf { it.changed.size })
    }

    @Test fun `full map goes in pages of 128`() {
        val pages = MeshRouteDeltaRules.pages((0 until 300).map { adv("d$it") })
        assertEquals(listOf(128, 128, 44), pages.map { it.size })
        assertEquals(1, MeshRouteDeltaRules.pages(emptyList()).size)
    }

    @Test fun `numbers go up per neighbour and the full map comes every 60 s`() {
        val sender = MeshRouteDeltaSender()
        assertTrue(sender.needsFull("p", now))
        sender.markFull("p", now)
        assertFalse(sender.needsFull("p", now + 59_000L))
        assertTrue(sender.needsFull("p", now + 60_000L))
        assertEquals(1L, sender.nextSeq("p"))
        assertEquals(2L, sender.nextSeq("p"))
        assertEquals(1L, sender.nextSeq("q"))
        assertEquals(2L, sender.currentSeq("p"))
    }

    @Test fun `a phone that misses a number asks for the full map`() {
        val rx = MeshRouteDeltaReceiver()
        rx.onFull("p", "session-1", 0L)
        assertTrue(rx.onDelta("p", "session-1", 1L))
        assertTrue(rx.onDelta("p", "session-1", 2L))
        assertFalse(rx.onDelta("p", "session-1", 4L)) // 3 was lost
        assertTrue(rx.onDelta("p", "session-1", 5L))
        assertTrue(rx.onDelta("p", "session-1", 3L)) // late, nothing missed
        // A restarted sender (new session) before its full map = ask.
        assertFalse(rx.onDelta("p", "session-2", 1L))
    }

    @Test fun `full map requests are limited to one per 15 s`() {
        val rx = MeshRouteDeltaReceiver()
        assertTrue(rx.mayRequestFull("p", now))
        rx.onFull("p", "session-1", 0L)
        assertTrue(rx.mayRequestFull("p", now))
        assertFalse(rx.mayRequestFull("p", now + 5_000L))
        assertTrue(rx.mayRequestFull("p", now + 15_000L))
        val tx = MeshRouteDeltaSender()
        tx.markFull("p", now)
        assertTrue(tx.requestFull("p", now))
        assertTrue(tx.needsFull("p", now))
        tx.markFull("p", now)
        assertFalse(tx.requestFull("p", now + 1_000L))
        assertFalse(tx.needsFull("p", now + 1_000L))
    }

    @Test fun `older phones still fit in the admission window`() {
        // 6 deltas + 12 extra + 8 pages + 2 requests = 28, and new limit is 60.
        val policy = MeshRouteAdvertisementPolicy()
        var accepted = 0
        for (i in 1..40) {
            if (policy.evaluate("peer", "session-abc", i.toLong(), now, 128, now).accepted) accepted++
        }
        assertEquals(40, accepted)
        assertEquals(128, MeshLimits.MAX_ROUTE_ADVERTISEMENT_ROUTES)
        assertEquals(90_000L, MeshLimits.ROUTE_ADVERTISEMENT_MAX_AGE_MS)
    }

    // ------------------------------------------------ 160.2 two-level map

    private fun learned(dest: String, hop: String, seen: Long) =
        MeshRoute(dest, hop, 2, now + 60_000L, seen, seen, listOf("me", hop, dest))

    @Test fun `the map holds 1024 places and an idle route makes room`() {
        assertEquals(1024, MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS)
        val table = MeshRouteTable { "me" }
        val old = now - 120_000L
        for (i in 0 until 1024) assertTrue(table.upsert("d$i", learned("d$i", "h${i % 40}", old + i)))
        assertTrue(table.upsert("new", learned("new", "h1", now)))
        assertEquals(1024, table.all().size)
        assertNull(table["d0"]) // the least recently seen one went
        assertNotNull(table["d1"])
    }

    @Test fun `fresh routes are never pushed out`() {
        val table = MeshRouteTable { "me" }
        for (i in 0 until 1024) assertTrue(table.upsert("d$i", learned("d$i", "h${i % 40}", now)))
        assertFalse(table.upsert("new", learned("new", "h1", now)))
        assertNotNull(table["d0"])
    }

    @Test fun `one next hop can carry the whole map`() {
        val table = MeshRouteTable { "me" }
        for (i in 0 until 400) assertTrue(table.upsert("d$i", learned("d$i", "host", now)))
        assertEquals(400, table.all().size)
    }

    private class Recording : MeshTransport {
        override val name = "test"
        val sent = mutableListOf<String>()
        override fun isPeerAvailable(nodeId: String) = true
        override fun send(peerNodeId: String, packet: MeshPacket): Boolean { sent += peerNodeId; return true }
        override fun disconnect(peerNodeId: String) {}
    }

    private fun packet(type: String = "direct_message", dest: String = "far") = MeshPacket.new(
        sourceNodeId = "me", destinationNodeId = dest, type = type,
        payload = JSONObject().put("recipient_id", dest).put(MeshPacket.MESH_PATH_KEY, JSONArray().put("me")),
        ttl = MeshLimits.MAX_TTL,
    )

    private fun registry(vararg ids: String) = MeshPeerRegistry().apply {
        ids.forEach { connected(it, MeshTransportPolicy.WIFI_DIRECT); available(it, MeshTransportPolicy.WIFI_DIRECT) }
    }

    @Test fun `no route at all - the group host carries it and the neighbours are asked`() {
        val transport = Recording()
        val asked = mutableListOf<String>()
        val router = MeshRouter({ "me" }, MeshRouteTable { "me" }, registry("host"), transport,
            enqueue = { true }, defaultNextHop = { "host" }, onNoRoute = { asked += it })
        assertEquals(MeshRouteResult.FORWARDED, router.route(packet()))
        assertEquals(listOf("host"), transport.sent)
        assertEquals(listOf("far"), asked)
    }

    @Test fun `no default for this packet - it waits in the outbox as before`() {
        val transport = Recording()
        var queued = 0
        val router = MeshRouter({ "me" }, MeshRouteTable { "me" }, registry("host"), transport,
            enqueue = { queued++; true }, defaultNextHop = { null })
        assertEquals(MeshRouteResult.QUEUED, router.route(packet()))
        assertEquals(1, queued)
        assertTrue(transport.sent.isEmpty())
    }

    @Test fun `the default hop is never used when a route exists`() {
        val table = MeshRouteTable { "me" }
        table.upsert("far", MeshRoute("far", "b", 2, now + 60_000L, now, now, listOf("me", "b", "far")))
        val transport = Recording()
        val router = MeshRouter({ "me" }, table, registry("host", "b"), transport, defaultNextHop = { "host" })
        assertEquals(MeshRouteResult.FORWARDED, router.route(packet()))
        assertEquals(listOf("b"), transport.sent)
    }

    @Test fun `the default hop never sends a packet back where it came from`() {
        val transport = Recording()
        var queued = 0
        val router = MeshRouter({ "me" }, MeshRouteTable { "me" }, registry("host"), transport,
            enqueue = { queued++; true }, defaultNextHop = { "host" })
        val incoming = MeshPacket.new(
            sourceNodeId = "host", destinationNodeId = "far", type = "direct_message",
            payload = JSONObject().put("recipient_id", "far").put(MeshPacket.MESH_PATH_KEY, JSONArray().put("host")),
            ttl = MeshLimits.MAX_TTL,
        ).copy(nextHopNodeId = "me", hopCount = 1, ttl = MeshLimits.MAX_TTL - 1)
        assertEquals(MeshRouteResult.QUEUED, router.route(incoming, incomingPeerId = "host"))
        assertTrue(transport.sent.isEmpty())
    }

    @Test fun `who can reach X - ask once per 30 s and answers only for open questions`() {
        val lookup = MeshRouteLookup()
        val id = lookup.ask("far", now)
        assertNotNull(id)
        assertNull(lookup.onAnswer("0123456789abcdef", "far", now))
        assertNull(lookup.onAnswer(id!!, "other", now))
        val pending = lookup.onAnswer(id, "far", now + 1_000L)
        assertNotNull(pending)
        assertNull(pending!!.askedBy)
        assertNull(lookup.onAnswer(id, "far", now + 1_000L)) // only once
        assertNull(lookup.ask("far", now + 10_000L))
        val again = lookup.ask("far", now + 30_000L)
        assertNotNull(again)
        // An answer that comes too late (after 10 s) is ignored.
        assertNull(lookup.onAnswer(again!!, "far", now + 41_000L))
    }

    @Test fun `a neighbour answers, passes on once, and drops repeats`() {
        val lookup = MeshRouteLookup()
        val q = "00000000000000a1"
        assertEquals(MeshRouteLookup.QueryAction.ANSWER, lookup.onQuery("p", q, "far", 2, true, now))
        assertEquals(MeshRouteLookup.QueryAction.DROP, lookup.onQuery("p", q, "far", 2, true, now))
        assertEquals(MeshRouteLookup.QueryAction.PASS_ON, lookup.onQuery("p", "00000000000000a2", "far", 2, false, now))
        assertEquals("p", lookup.onAnswer("00000000000000a2", "far", now)?.askedBy)
        assertEquals(MeshRouteLookup.QueryAction.NOTHING, lookup.onQuery("p", "00000000000000a3", "far", 1, false, now))
        assertEquals(MeshRouteLookup.QueryAction.DROP, lookup.onQuery("p", "00000000000000a4", "far", 3, false, now))
        assertEquals(MeshRouteLookup.QueryAction.DROP, lookup.onQuery("p", "bad", "far", 2, false, now))
    }

    @Test fun `one neighbour can ask at most 20 times a minute`() {
        val lookup = MeshRouteLookup()
        var answered = 0
        for (i in 0 until 30) {
            val id = "%016x".format(i + 1)
            if (lookup.onQuery("p", id, "far", 2, true, now) == MeshRouteLookup.QueryAction.ANSWER) answered++
        }
        assertEquals(20, answered)
        assertEquals(MeshRouteLookup.QueryAction.ANSWER, lookup.onQuery("p", "%016x".format(99), "far", 2, true, now + 60_000L))
    }

    @Test fun `answers are kept 5 min`() {
        assertEquals(5L * 60L * 1000L, MeshRouteLookupRules.ANSWER_TTL_MS)
        assertEquals(2, MeshRouteLookupRules.MAX_TTL)
    }

    // ------------------------------------------------ 160.3 quieter Wi-Fi

    @Test fun `beacon every 3 s, 10 s or 15 s by phones seen`() {
        assertEquals(3_000L, MeshTransportPolicy.lanBeaconIntervalMs(0))
        assertEquals(3_000L, MeshTransportPolicy.lanBeaconIntervalMs(9))
        assertEquals(10_000L, MeshTransportPolicy.lanBeaconIntervalMs(10))
        assertEquals(10_000L, MeshTransportPolicy.lanBeaconIntervalMs(49))
        assertEquals(15_000L, MeshTransportPolicy.lanBeaconIntervalMs(50))
        assertEquals(15_000L, MeshTransportPolicy.lanBeaconIntervalMs(300))
    }

    @Test fun `beacon jitter stays within 20 percent`() {
        assertEquals(8_000L, MeshTransportPolicy.jitteredBeaconMs(20, 0.0))
        assertEquals(12_000L, MeshTransportPolicy.jitteredBeaconMs(20, 1.0))
        for (i in 0..100) {
            val ms = MeshTransportPolicy.jitteredBeaconMs(60, i / 100.0)
            assertTrue(ms in 12_000L..18_000L)
        }
    }

    @Test fun `phones are forgotten only after about 3 missed beacons`() {
        assertEquals(12_000L, MeshTransportPolicy.lanEndpointRetentionMs(3))
        assertEquals(36_000L, MeshTransportPolicy.lanEndpointRetentionMs(20))
        assertEquals(54_000L, MeshTransportPolicy.lanEndpointRetentionMs(80))
    }

    @Test fun `about 30 direct links, more only when a message needs one`() {
        assertTrue(MeshTransportPolicy.mayDialContact(29, needed = false))
        assertFalse(MeshTransportPolicy.mayDialContact(30, needed = false))
        assertTrue(MeshTransportPolicy.mayDialContact(30, needed = true))
        assertEquals(3, MeshRelayPolicy.MAX_RELAY_LINKS)
    }

    // ------------------------------------------------ signed device id

    private val keyHex = "11".repeat(32)

    @Test fun `link keys parse only with good ids and 32 bytes`() {
        assertNotNull(MeshLinkAuth.parse("AAAAAAAAAAA", "BBBBBBBBBBB", keyHex))
        assertNull(MeshLinkAuth.parse("bad id", "BBBBBBBBBBB", keyHex))
        assertNull(MeshLinkAuth.parse("AAAAAAAAAAA", "BBBBBBBBBBB", "11"))
    }

    @Test fun `both phones find the same shared key`() {
        val alice = listOf(MeshLinkAuth.parse("AliceKey1__", "BobKey1____", keyHex)!!)
        val bob = listOf(
            MeshLinkAuth.parse("BobKey0____", "AliceKey0__", "22".repeat(32))!!,
            MeshLinkAuth.parse("BobKey1____", "AliceKey1__", keyHex)!!,
        )
        val picked = MeshLinkAuth.match(bob, MeshLinkAuth.offers(alice))
        assertNotNull(picked)
        assertEquals("BobKey1____", picked!!.ownKid)
        assertNull(MeshLinkAuth.match(alice, listOf("Nobody_____.Other______")))
    }

    @Test fun `the HMAC proves the id and binds both random numbers`() {
        val key = MeshLinkAuth.parse("AAAAAAAAAAA", "BBBBBBBBBBB", keyHex)!!.key
        val cn = MeshLinkAuth.newNonce()
        val sn = MeshLinkAuth.newNonce()
        assertTrue(MeshLinkAuth.validNonce(cn))
        val mac = MeshLinkAuth.mac(key, "c", "alice", "bob", cn, sn)
        assertTrue(MeshLinkAuth.verify(key, "c", "alice", "bob", cn, sn, mac))
        assertFalse(MeshLinkAuth.verify(key, "c", "mallory", "bob", cn, sn, mac))
        assertFalse(MeshLinkAuth.verify(key, "s", "alice", "bob", cn, sn, mac))
        assertFalse(MeshLinkAuth.verify(key, "c", "alice", "bob", cn, MeshLinkAuth.newNonce(), mac))
        val other = MeshLinkAuth.parse("AAAAAAAAAAA", "BBBBBBBBBBB", "33".repeat(32))!!.key
        assertFalse(MeshLinkAuth.verify(other, "c", "alice", "bob", cn, sn, mac))
        assertFalse(MeshLinkAuth.verify(key, "c", "alice", "bob", cn, sn, null))
    }

    @Test fun `when both have keys the HMAC is required`() {
        assertEquals(MeshLinkAuth.Verdict.VERIFIED, MeshLinkAuth.decide(true, true, true, true, false).verdict)
        assertEquals(MeshLinkAuth.Verdict.REJECT, MeshLinkAuth.decide(true, true, true, false, false).verdict)
    }

    @Test fun `older phones connect the old way until they once passed`() {
        assertEquals(MeshLinkAuth.Decision(MeshLinkAuth.Verdict.LEGACY, "old_phone"), MeshLinkAuth.decide(true, false, false, false, false))
        assertEquals(MeshLinkAuth.Decision(MeshLinkAuth.Verdict.LEGACY, "no_shared_key"), MeshLinkAuth.decide(true, true, false, false, false))
        assertEquals(MeshLinkAuth.Decision(MeshLinkAuth.Verdict.REJECT, "auth_required"), MeshLinkAuth.decide(true, false, false, false, true))
        assertEquals(MeshLinkAuth.Decision(MeshLinkAuth.Verdict.REJECT, "auth_required"), MeshLinkAuth.decide(true, true, false, false, true))
        // No key here (stranger, or keys not loaded yet): the old way.
        assertEquals(MeshLinkAuth.Verdict.LEGACY, MeshLinkAuth.decide(false, true, false, false, true).verdict)
    }

    // ------------------------------------------------ 160.7 300 phones

    /** A tiny copy of the service's route advertisement logic. */
    private class Phone(val id: String) {
        val table = MeshRouteTable { id }
        val tx = MeshRouteDeltaSender()
        val rx = MeshRouteDeltaReceiver()
        val links = linkedSetOf<String>()
        var routesReceived = 0

        fun advertisable(): List<MeshAdvertisedRoute> = table.all().values.mapNotNull { candidates ->
            candidates.filter { it.state == MeshRouteState.ACTIVE }
                .minWithOrNull(compareBy<MeshRoute> { it.hopCount }.thenBy { it.nextHopNodeId })
        }.sortedWith(compareBy<MeshRoute> { it.hopCount }.thenBy { it.destinationNodeId })
            .map { MeshAdvertisedRoute(it.destinationNodeId, it.hopCount, it.routeVersion, it.path) }

        /** Same checks as updateRoutesFromAdvertisement. Returns true if anything changed. */
        fun apply(from: String, routes: List<MeshAdvertisedRoute>, withdrawn: List<String>, now: Long): Boolean {
            routesReceived += routes.size
            var changed = false
            for (r in routes) {
                if (r.destination == id || r.destination == from) continue
                if (r.hopCount < 1 || r.hopCount > MeshLimits.MAX_HOPS - 1) continue
                if (r.path.firstOrNull() != from || r.path.lastOrNull() != r.destination || r.path.size != r.hopCount + 1) continue
                val full = listOf(id) + r.path
                if (full.distinct().size != full.size) continue
                if (table.upsert(r.destination, MeshRoute(r.destination, from, r.hopCount + 1, now + MeshRouteDeltaRules.ROUTE_TTL_MS, now, r.routeVersion, full))) changed = true
            }
            for (d in withdrawn) if (d != id && table.remove(d, from).isNotEmpty()) changed = true
            return changed
        }
    }

    private class Net(val now: Long) {
        val phones = LinkedHashMap<String, Phone>()
        var dropNextDeltaTo: String? = null
        var fullRequests = 0

        fun add(id: String) { phones[id] = Phone(id) }

        fun link(a: String, b: String) {
            val pa = phones.getValue(a); val pb = phones.getValue(b)
            pa.links += b; pb.links += a
            pa.table.upsert(b, MeshRoute(b, b, 1, now + 300_000L, now, now, listOf(a, b)))
            pb.table.upsert(a, MeshRoute(a, a, 1, now + 300_000L, now, now, listOf(b, a)))
            pa.tx.forget(b); pb.tx.forget(a); pa.rx.forget(b); pb.rx.forget(a)
        }

        fun leave(id: String) {
            val gone = phones.remove(id) ?: return
            for (n in gone.links) {
                val p = phones[n] ?: continue
                p.links -= id
                p.table.removeVia(id)
                p.tx.forget(id); p.rx.forget(id)
            }
        }

        /** One 10 s tick: every phone sends full pages or its changes. */
        fun round(): Boolean {
            var changed = false
            val outgoing = ArrayList<Triple<String, String, Pair<List<MeshAdvertisedRoute>, List<String>>>>()
            val modes = HashMap<Pair<String, String>, Pair<Boolean, Long>>()
            for (p in phones.values) {
                val current = p.advertisable()
                val chunks = p.tx.chunks(p.tx.diff(current))
                for (n in p.links) {
                    if (p.tx.needsFull(n, now)) {
                        val seq = p.tx.currentSeq(n)
                        MeshRouteDeltaRules.pages(current).forEach { page ->
                            outgoing += Triple(p.id, n, page to emptyList())
                            modes[p.id to n] = true to seq
                        }
                        p.tx.markFull(n, now)
                    } else for (c in chunks) {
                        val seq = p.tx.nextSeq(n)
                        if (dropNextDeltaTo == n) { dropNextDeltaTo = null; continue } // lost on the air
                        if (!phones.getValue(n).rx.onDelta(p.id, "s-${p.id}", seq)) {
                            fullRequests++
                            p.tx.requestFull(n, now)
                        }
                        outgoing += Triple(p.id, n, c.changed to c.withdrawn)
                    }
                }
            }
            for ((from, to, msg) in outgoing) {
                val target = phones[to] ?: continue
                modes[from to to]?.let { (full, seq) -> if (full) target.rx.onFull(from, "s-$from", seq) }
                if (target.apply(from, msg.first, msg.second, now)) changed = true
            }
            return changed
        }

        fun converge(maxRounds: Int = 20): Int {
            var rounds = 0
            while (rounds < maxRounds) {
                rounds++
                if (!round() && rounds > 2) break
            }
            return rounds
        }

        /** Follows next hops; returns hops used, or -1. */
        fun deliver(from: String, to: String): Int {
            var cur = from
            var hops = 0
            val seen = HashSet<String>()
            while (cur != to) {
                if (!seen.add(cur) || hops > MeshLimits.MAX_HOPS) return -1
                val next = phones[cur]?.table?.get(to)?.nextHopNodeId ?: return -1
                cur = next
                hops++
            }
            return hops
        }
    }

    /** 38 groups (a host + up to 7 members), hosts joined by bridges in a tree. */
    private fun build300(net: Net) {
        val hosts = (0 until 38).map { "h%02d".format(it) }
        hosts.forEach(net::add)
        for (i in 1 until hosts.size) {
            val parent = if (i <= 6) 0 else 1 + (i - 7) % 6
            net.link(hosts[i], hosts[parent])
        }
        var made = hosts.size
        var m = 0
        while (made < 300) {
            val host = hosts[m % hosts.size]
            val id = "m%03d".format(m)
            net.add(id); net.link(id, host)
            made++; m++
        }
        assertEquals(300, net.phones.size)
    }

    private fun assertAllReach(net: Net) {
        val ids = net.phones.keys.toList()
        var worst = 0
        for (a in ids) for (b in ids) {
            if (a == b) continue
            val hops = net.deliver(a, b)
            assertTrue("$a -> $b not delivered", hops in 1..MeshLimits.MAX_HOPS)
            if (hops > worst) worst = hops
        }
        assertTrue(worst <= 8)
    }

    @Test fun `300 phones - everyone reaches everyone within 8 hops`() {
        val net = Net(now)
        build300(net)
        val rounds = net.converge()
        assertTrue("took $rounds rounds", rounds <= 10)
        assertAllReach(net)
        // Quiet network: a tick carries no routes at all.
        val before = net.phones.values.sumOf { it.routesReceived }
        assertFalse(net.round())
        assertEquals(before, net.phones.values.sumOf { it.routesReceived })
    }

    @Test fun `300 phones - a phone leaves and one joins without route loss`() {
        val net = Net(now)
        build300(net)
        net.converge()
        net.leave("m010")
        net.converge()
        for (p in net.phones.values) assertNull("${p.id} still has a route to m010", p.table["m010"])
        net.add("new1"); net.link("new1", "h09")
        net.converge()
        assertAllReach(net)
    }

    @Test fun `a lost update is noticed and fixed by the full map`() {
        val net = Net(now)
        build300(net)
        net.converge()
        net.dropNextDeltaTo = "m020"
        net.add("late"); net.link("late", "h05")
        net.converge()
        assertTrue(net.fullRequests >= 1)
        assertNotNull(net.phones.getValue("m020").table["late"])
        assertAllReach(net)
    }
}
