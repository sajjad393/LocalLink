package com.sajjad.locallink.mesh

/** Central validation rules for mesh node, packet and protocol identifiers. */
object MeshIdPolicy {
    const val MAX_ID_LENGTH = 128
    const val MAX_TYPE_LENGTH = 128

    fun isValid(value: String): Boolean {
        val v = value.trim()
        return v.isNotEmpty() && v.length <= MAX_ID_LENGTH &&
            v.none { it.isISOControl() || it.isWhitespace() }
    }

    fun isValidType(value: String): Boolean {
        val v = value.trim()
        return v.isNotEmpty() && v.length <= MAX_TYPE_LENGTH &&
            v.none { it.isISOControl() || it.isWhitespace() }
    }
}
