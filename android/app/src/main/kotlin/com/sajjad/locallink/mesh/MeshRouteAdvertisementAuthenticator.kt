package com.sajjad.locallink.mesh

import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** HMAC authentication for the per-hop route control plane. */
object MeshRouteAdvertisementAuthenticator {
    private const val DOMAIN = "locallink-route-control-v2"
    private const val HEX_LENGTH = 64

    fun sign(advertisement: JSONObject, sharedKey: String): String {
        require(sharedKey.isNotBlank()) { "shared key required" }
        return hmac(sharedKey, canonicalWithoutAuth(advertisement))
    }

    fun withAuth(advertisement: JSONObject, sharedKey: String): JSONObject =
        JSONObject(advertisement.toString()).put("route_auth", sign(advertisement, sharedKey))

    fun verify(advertisement: JSONObject, sharedKey: String): Boolean {
        if (sharedKey.isBlank()) return false
        val provided = advertisement.optString("route_auth").trim()
        if (provided.length != HEX_LENGTH || provided.any { it !in '0'..'9' && it !in 'a'..'f' && it !in 'A'..'F' }) return false
        val expected = sign(advertisement, sharedKey)
        return MessageDigest.isEqual(
            expected.toByteArray(StandardCharsets.US_ASCII),
            provided.toByteArray(StandardCharsets.US_ASCII),
        )
    }

    private fun canonicalWithoutAuth(advertisement: JSONObject): String {
        val copy = JSONObject(advertisement.toString()).apply { remove("route_auth") }
        return DOMAIN + "|" + canonicalJson(copy)
    }

    private fun hmac(key: String, input: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key.toByteArray(StandardCharsets.UTF_8), "HmacSHA256"))
        return mac.doFinal(input.toByteArray(StandardCharsets.UTF_8)).joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun canonicalJson(value: Any?): String = when (value) {
        is JSONObject -> {
            val keys = mutableListOf<String>()
            val iterator = value.keys()
            while (iterator.hasNext()) keys.add(iterator.next())
            keys.sort()
            buildString {
                append('{')
                keys.forEachIndexed { index, key ->
                    if (index > 0) append(',')
                    append(JSONObject.quote(key)).append(':').append(canonicalJson(value.opt(key)))
                }
                append('}')
            }
        }
        is JSONArray -> buildString {
            append('[')
            for (i in 0 until value.length()) {
                if (i > 0) append(',')
                append(canonicalJson(value.opt(i)))
            }
            append(']')
        }
        JSONObject.NULL -> "null"
        is String -> JSONObject.quote(value)
        is Number, is Boolean -> value.toString()
        else -> JSONObject.quote(value.toString())
    }
}
