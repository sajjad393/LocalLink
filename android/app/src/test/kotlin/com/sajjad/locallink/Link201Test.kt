package com.sajjad.locallink

import com.sajjad.locallink.mesh.MeshTransportPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Link201Test {
    private val wd = MeshTransportPolicy.WIFI_DIRECT

    // ---------------- B: no re-dial of a working Wi-Fi Direct link ----------------

    @Test fun wifi_direct_client_link_matches_by_socket_address() {
        // ownerAddress is null on a Wi-Fi Direct client link by design.
        assertTrue(MeshTransportPolicy.linksOwner("192.168.49.1", null, wd, "192.168.49.1"))
        assertTrue(MeshTransportPolicy.linksOwner("192.168.49.1", null, wd, "/192.168.49.1"))
    }

    @Test fun owner_address_still_matches() {
        assertTrue(MeshTransportPolicy.linksOwner("192.168.49.1", "192.168.49.1", "lan", null))
    }

    @Test fun other_links_do_not_match() {
        assertFalse(MeshTransportPolicy.linksOwner("192.168.49.1", null, wd, "192.168.49.7"))
        assertFalse(MeshTransportPolicy.linksOwner("192.168.49.1", null, "lan", "192.168.49.1"))
        assertFalse(MeshTransportPolicy.linksOwner(null, null, wd, "192.168.49.1"))
        assertFalse(MeshTransportPolicy.linksOwner("", null, wd, ""))
    }

    // ---------------- A3: group lost log ----------------

    @Test fun group_lost_only_on_formed_to_gone() {
        assertTrue(WdGroupLost.lost(true, false))
        assertFalse(WdGroupLost.lost(null, false))
        assertFalse(WdGroupLost.lost(false, false))
        assertFalse(WdGroupLost.lost(true, true))
    }

    @Test fun group_lost_line() {
        val d = WdGroupLost.detail("DISCONNECTED", null, " group removed ")
        assertEquals("state=DISCONNECTED reason=- extra=group_removed", d)
        assertEquals("WD_GROUP_LOST was=host p2p=on $d", WdGroupLost.line(true, true, d))
        assertEquals("WD_GROUP_LOST was=member p2p=off $d", WdGroupLost.line(false, false, d))
    }
}
