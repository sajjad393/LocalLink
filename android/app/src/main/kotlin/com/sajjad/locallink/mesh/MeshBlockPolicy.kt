package com.sajjad.locallink.mesh

/**
 * Bundle 212: plain frames that go ONE step only (straight between two
 * linked phones, on any link: contact, stranger relay or a blocked phone's
 * relay link), never routed or passed on by the link layer. The 195c name
 * question / answer plus the admin block spread frames (signed, not secret).
 * Bundle 213 adds its update / version frames here.
 */
object MeshOneStep {
    const val ADMIN_BLOCK_DIGEST: String = "admin_block_digest"
    const val ADMIN_BLOCK_RECORDS: String = "admin_block_records"
    const val ADMIN_BLOCK_GOT: String = "admin_block_got"

    // Bundle 213: minimum app version + "get the new LinkUp" frames.
    const val VERSION_DIGEST: String = "version_digest"
    const val VERSION_RULE: String = "version_rule"
    const val APP_UPDATE_REQUEST: String = "app_update_request"
    const val APP_UPDATE_ANSWER: String = "app_update_answer"
    const val APP_UPDATE_OFFER: String = "app_update_offer"

    // Bundle 214: admin crown cards (server-signed, no secrets).
    const val ADMIN_BADGE_DIGEST: String = "admin_badge_digest"
    const val ADMIN_BADGE_RECORDS: String = "admin_badge_records"

    private val adminTypes = setOf(ADMIN_BLOCK_DIGEST, ADMIN_BLOCK_RECORDS, ADMIN_BLOCK_GOT)
    private val versionTypes = setOf(VERSION_DIGEST, VERSION_RULE, APP_UPDATE_REQUEST, APP_UPDATE_ANSWER, APP_UPDATE_OFFER)

    fun isAdminBlock(type: String?): Boolean = type != null && type in adminTypes

    fun isVersion(type: String?): Boolean = type != null && type in versionTypes

    private val badgeTypes = setOf(ADMIN_BADGE_DIGEST, ADMIN_BADGE_RECORDS)

    fun isAdminBadge(type: String?): Boolean = type != null && type in badgeTypes

    // Bundle 220: admin action cards, their "done" receipts and the digest
    // (signed; each phone passes them on itself, one step at a time).
    const val ADMIN_ACT_DIGEST: String = "admin_act_digest"
    const val ADMIN_ACT_CARDS: String = "admin_act_cards"
    const val ADMIN_ACT_DONE: String = "admin_act_done"

    // Bundle 221: chat answer parts / "I carry" lists / acks (one part per
    // frame; each phone passes them on itself).
    const val ADMIN_ACT_PARTS: String = "admin_act_parts"

    private val actionTypes = setOf(ADMIN_ACT_DIGEST, ADMIN_ACT_CARDS, ADMIN_ACT_DONE, ADMIN_ACT_PARTS)

    fun isAdminAction(type: String?): Boolean = type != null && type in actionTypes

    fun isOneStep(type: String?): Boolean = MeshRelayPolicy.isNameQuestion(type) || isAdminBlock(type) || isVersion(type) || isAdminBadge(type) || isAdminAction(type)

    /** Came straight from the phone on this link and is for this phone. */
    fun isOneStepIn(type: String?, sourceId: String, destinationId: String, linkPeerId: String, selfId: String): Boolean =
        isOneStep(type) && selfId.isNotBlank() && sourceId == linkPeerId && destinationId == selfId

    /** May this phone send it on the link to [linkPeerId]? */
    fun canSendOneStep(type: String?, sourceId: String, destinationId: String, linkPeerId: String, selfId: String): Boolean =
        isOneStep(type) && selfId.isNotBlank() && sourceId == selfId && destinationId == linkPeerId
}

/**
 * Bundle 212 (D2): a blocked phone (admin block or my own block) still
 * works as a mesh node for others. Its link is relay-only (it carries only
 * sealed packets it can't read), and any packet from or to a blocked person
 * is dropped at the first phone that sees it. [MeshRelayPolicy.trustFor] is
 * not changed (old tests); this wraps it.
 */
object MeshBlockPolicy {
    /**
     * Trust for a peer at link time, or null = refuse. A blocked peer is
     * treated as a stranger: relay when both phones offer relaying, it is
     * not paused and there is room; never a contact link.
     */
    fun trust(
        peerId: String,
        isContact: Boolean,
        isBlocked: Boolean,
        peerOffersRelay: Boolean,
        relayLinks: Int,
        isPaused: Boolean = false,
    ): String? = MeshRelayPolicy.trustFor(
        peerId = peerId,
        isContact = isContact && !isBlocked,
        isBlocked = false,
        peerOffersRelay = peerOffersRelay,
        relayLinks = relayLinks,
        isPaused = isPaused,
    )

    /** A contact link to a blocked peer is closed (it comes back as relay). */
    fun closeLink(trust: String, isBlocked: Boolean): Boolean =
        isBlocked && trust != MeshRelayPolicy.TRUST_RELAY

    /** A blocked node may still be dialled as a relay. */
    fun mayDialRelay(isPaused: Boolean): Boolean = MeshRelayPolicy.RELAY_ENABLED && !isPaused

    /**
     * First-hop drop: a routed packet whose origin or final target is a
     * blocked person. One-step frames are exempt (never routed).
     */
    fun dropAtFirstHop(type: String?, sourceId: String, destinationId: String, blocked: Set<String>): Boolean {
        if (MeshOneStep.isOneStep(type)) return false
        if (blocked.isEmpty()) return false
        return (sourceId.isNotBlank() && sourceId in blocked) || (destinationId.isNotBlank() && destinationId in blocked)
    }

    /** May the link to [peerTrust] be the next hop for [type]? */
    fun canUseNextHop(peerTrust: String, type: String?, oneStep: Boolean): Boolean =
        MeshRelayPolicy.canCarry(peerTrust, type) || oneStep
}
