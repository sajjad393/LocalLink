package com.sajjad.locallink

/**
 * Bundle 193 (logs only): words for the file send / receive log lines, so a
 * phone log shows which copy was sent, if a send continued or started again,
 * and that both phones ended with the same bytes (size + short fingerprint).
 *
 * - FILE_SEND_START transfer=<12> file=<12> size=<n> sha=<8> chunks=<n> done=<n> reuse=y|n busy=y|n src=<kind>
 * - FILE_SEND_REPLACED transfer=<12> old_size=<n> old_sha=<8> old_done=<n> old_src=<kind> new_size=<n> new_sha=<8> new_src=<kind>
 * - FILE_SEND_RESTORED transfer=<12> size=<n> sha=<8> done=<n>/<total> src=<kind>
 * - FILE_SEND_RESTORE_DROPPED transfer=<12> reason=<why>
 * - FILE_SEND_SOURCE_BAD transfer=<12> reason=missing|size_changed|content_changed size=<n> now=<n> src=<kind>
 * - FILE_SEND_DONE transfer=<12> size=<n> sha=<8> chunks=<n>
 * - FILE_RECEIVE_START transfer=<12> size=<n> sha=<8> chunks=<n> resumed=y|n have=<n>
 * - FILE_CHUNK_IGNORED transfer=<12> reason=different_file have_size=<n> have_sha=<8> got_size=<n> got_sha=<8>
 * - FILE_RECEIVED_OK transfer=<12> size=<n> sha=<8> chunks=<n>
 *
 * src: staged (LinkUp's own copy), view (a temporary open copy of the locked
 * file), locked (.enc), received (a file this phone received), picker
 * (gallery/cache path), other.
 */
object FileSendLogPolicy {
    fun srcKind(path: String?): String {
        val p = path?.replace('\\', '/')?.trim().orEmpty()
        if (p.isEmpty()) return "-"
        val name = p.substringAfterLast('/')
        return when {
            p.endsWith(".enc") -> "locked"
            name.startsWith(".view-") -> "view"
            p.contains("/attachments/") && name.startsWith("outbox-") -> "staged"
            p.contains("/locallink_direct_files/") -> "received"
            p.contains("/cache/") -> "picker"
            else -> "other"
        }
    }

    fun id(value: String?): String = value?.trim()?.take(12)?.ifEmpty { "-" } ?: "-"
    fun sha(value: String?): String = value?.trim()?.take(8)?.ifEmpty { "-" } ?: "-"
    private fun yn(b: Boolean) = if (b) "y" else "n"

    fun sendStart(transfer: String, file: String, size: Long, sha: String, chunks: Int, done: Int, reuse: Boolean, busy: Boolean, path: String?): String =
        "FILE_SEND_START transfer=${id(transfer)} file=${id(file)} size=$size sha=${sha(sha)} chunks=$chunks done=$done reuse=${yn(reuse)} busy=${yn(busy)} src=${srcKind(path)}"

    fun sendReplaced(transfer: String, oldSize: Long, oldSha: String, oldDone: Int, oldPath: String?, newSize: Long, newSha: String, newPath: String?): String =
        "FILE_SEND_REPLACED transfer=${id(transfer)} old_size=$oldSize old_sha=${sha(oldSha)} old_done=$oldDone old_src=${srcKind(oldPath)} new_size=$newSize new_sha=${sha(newSha)} new_src=${srcKind(newPath)}"

    fun restored(transfer: String, size: Long, sha: String, done: Int, total: Int, path: String?): String =
        "FILE_SEND_RESTORED transfer=${id(transfer)} size=$size sha=${sha(sha)} done=$done/$total src=${srcKind(path)}"

    fun restoreDropped(transfer: String, reason: String): String =
        "FILE_SEND_RESTORE_DROPPED transfer=${id(transfer)} reason=$reason"

    /** Why a saved source no longer matches, or null when it still does. */
    fun sourceProblem(exists: Boolean, sizeNow: Long, sizeWas: Long, shaSame: () -> Boolean): String? = when {
        !exists -> "missing"
        sizeNow != sizeWas -> "size_changed"
        !shaSame() -> "content_changed"
        else -> null
    }

    fun sourceBad(transfer: String, reason: String, sizeWas: Long, sizeNow: Long, path: String?): String =
        "FILE_SEND_SOURCE_BAD transfer=${id(transfer)} reason=$reason size=$sizeWas now=$sizeNow src=${srcKind(path)}"

    fun sendDone(transfer: String, size: Long, sha: String, chunks: Int): String =
        "FILE_SEND_DONE transfer=${id(transfer)} size=$size sha=${sha(sha)} chunks=$chunks"

    fun receiveStart(transfer: String, size: Long, sha: String, chunks: Int, resumed: Boolean, have: Int): String =
        "FILE_RECEIVE_START transfer=${id(transfer)} size=$size sha=${sha(sha)} chunks=$chunks resumed=${yn(resumed)} have=$have"

    fun chunkIgnored(transfer: String, haveSize: Long, haveSha: String, gotSize: Long, gotSha: String): String =
        "FILE_CHUNK_IGNORED transfer=${id(transfer)} reason=different_file have_size=$haveSize have_sha=${sha(haveSha)} got_size=$gotSize got_sha=${sha(gotSha)}"

    fun receivedOk(transfer: String, size: Long, sha: String, chunks: Int): String =
        "FILE_RECEIVED_OK transfer=${id(transfer)} size=$size sha=${sha(sha)} chunks=$chunks"
}
