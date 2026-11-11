package com.sajjad.locallink

import com.sajjad.locallink.mesh.NearbyGroupPolicy

/**
 * Bundle 260 (A6): after a force stop (or any app death) Android keeps the
 * Wi-Fi Direct group this phone hosted. Other phones stay members of a group
 * nobody runs. When the app starts again it closes such a group once - only
 * a LinkUp nearby group (`DIRECT-LL-` name) this phone owns, never another
 * app's group, never a group this phone is only a member of.
 */
object LeftoverGroupPolicy {
    fun shouldClose(formed: Boolean, owner: Boolean, name: String?): Boolean =
        formed && owner && (name ?: "").startsWith(NearbyGroupPolicy.NAME_PREFIX)

    fun line(name: String?, members: Int, ok: Boolean): String =
        "NEARBY group leftover_closed grp=${name ?: "-"} members=$members" +
            (if (ok) "" else " ok=n")
}
