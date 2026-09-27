package com.sajjad.locallink

import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** AUDIT-015: per-attachment key derivation and chunk authentication. */
internal object DirectFileSecurity {
    const val CRYPTO_VERSION = "v2"
    private const val KEY_LABEL = "locallink-file-key-v2"
    private const val AES_LABEL = "locallink-file-aes-v2"
    private const val AUTH_LABEL = "locallink-file-hmac-v2"
    private val random = SecureRandom()

    data class FileChunkContext(
        val transferId: String,
        val senderId: String,
        val recipientId: String,
        val fileId: String,
        val messageId: String,
        val fileName: String,
        val contentType: String,
        val size: Long,
        val sha256: String,
        val totalChunks: Int,
    )

    fun deriveFileKey(peerSecret: String, context: FileChunkContext): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(peerSecret.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        return mac.doFinal((KEY_LABEL + "|" + canonicalContext(context)).toByteArray(Charsets.UTF_8))
    }

    fun chunkAad(context: FileChunkContext, chunkIndex: Int): String =
        canonicalContext(context) + field("chunk_index", chunkIndex.toString()) + field("crypto_version", CRYPTO_VERSION)

    fun authTag(fileKey: ByteArray, aad: String, encryptedData: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(kdf(fileKey, AUTH_LABEL), "HmacSHA256"))
        return mac.doFinal((aad + encryptedData).toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    fun encryptChunk(data: ByteArray, fileKey: ByteArray, aad: String): String {
        val iv = ByteArray(12).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(kdf(fileKey, AES_LABEL), "AES"), GCMParameterSpec(128, iv))
        cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(iv + cipher.doFinal(data), Base64.NO_WRAP)
    }

    fun decryptChunk(encoded: String, fileKey: ByteArray, aad: String): ByteArray? {
        return try {
            val all = Base64.decode(encoded, Base64.DEFAULT)
            if (all.size < 28) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(kdf(fileKey, AES_LABEL), "AES"), GCMParameterSpec(128, all.copyOfRange(0, 12)))
            cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))
            cipher.doFinal(all.copyOfRange(12, all.size))
        } catch (_: Exception) { null }
    }

    private fun canonicalContext(c: FileChunkContext): String = buildString {
        append("locallink-direct-file-").append(CRYPTO_VERSION)
        append(field("transfer_id", c.transferId))
        append(field("sender_id", c.senderId))
        append(field("recipient_id", c.recipientId))
        append(field("file_id", c.fileId))
        append(field("message_id", c.messageId))
        append(field("file_name", c.fileName))
        append(field("content_type", c.contentType))
        append(field("size", c.size.toString()))
        append(field("sha256", c.sha256))
        append(field("total_chunks", c.totalChunks.toString()))
    }

    private fun field(name: String, value: String): String = "|$name=${value.length}:$value"

    private fun kdf(key: ByteArray, label: String): ByteArray =
        MessageDigest.getInstance("SHA-256").digest((label + "|").toByteArray(Charsets.UTF_8) + key)
}
