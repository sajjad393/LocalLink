package com.sajjad.locallink.mesh

import java.io.IOException
import java.io.Reader

/**
 * Bundle 229 (S1): size limits for the nearby link sockets (LAN, Wi-Fi
 * Direct, hotspot / local net).
 *
 * Before, every line was read with `BufferedReader.readLine()`, which keeps
 * a line in memory however long it is. A phone that never sends a newline
 * could fill the memory of a small phone. The read loop already threw away
 * lines over 256 KB, but only after keeping all of them.
 *
 * Now:
 * - handshake lines (hello / challenge / auth): at most [HANDSHAKE_MAX_CHARS],
 *   longer = the link attempt ends;
 * - data lines: up to [DATA_KEEP_MAX_CHARS] are read as before; longer lines
 *   are skipped WITHOUT being kept (the same "drop and go on" as before);
 *   past [DATA_HARD_MAX_CHARS] the link is closed.
 * - at most [MAX_PENDING_HANDSHAKES] incoming handshakes at the same time
 *   (working links are not counted).
 */
object LineLimits {
    /** Real handshake lines are below 2 KB. */
    const val HANDSHAKE_MAX_CHARS = 64 * 1024

    /** The same limit the read loop already used (`line.length > 256 * 1024` = dropped). */
    const val DATA_KEEP_MAX_CHARS = 256 * 1024

    /** One line this long is never real traffic: the link is closed. */
    const val DATA_HARD_MAX_CHARS = 8 * 1024 * 1024

    /** Incoming link attempts still in their handshake at the same time. */
    const val MAX_PENDING_HANDSHAKES = 24

    /** [inProgress] counts this attempt too. */
    fun handshakeAllowed(inProgress: Int): Boolean = inProgress <= MAX_PENDING_HANDSHAKES
}

/** A line went past the hard limit; the reader must not be used again. */
class LineTooLongException(val chars: Long, val max: Int) : IOException("line too long: more than $max chars")

/**
 * Reads lines like `BufferedReader.readLine()` (ends at `\n`, `\r` or
 * `\r\n`; a last line without an end is returned; `null` = end of stream),
 * but never keeps more than `keepMax` characters of one line.
 *
 * A read timeout (`SocketTimeoutException`) leaves the part already read in
 * place, so the next call goes on with the same line.
 */
class BoundedLineReader(private val source: Reader, bufferChars: Int = 8192) {
    private val buf = CharArray(bufferChars)
    private var pos = 0
    private var limit = 0
    private var line = StringBuilder()
    private var dropping = false
    private var droppedChars = 0L
    private var skipLf = false
    private var ended = false

    /** True when the last [readLine] skipped a line longer than its keepMax (it returned ""). */
    var droppedLast: Boolean = false
        private set

    /** Length of the skipped line when [droppedLast]. */
    var droppedLastChars: Long = 0L
        private set

    /**
     * The next line, or `null` at the end of the stream.
     * Longer than [keepMax]: skipped, returns "" with [droppedLast] = true.
     * Longer than [hardMax]: throws [LineTooLongException].
     */
    fun readLine(keepMax: Int, hardMax: Int = keepMax): String? {
        require(keepMax >= 0 && hardMax >= keepMax)
        droppedLast = false
        droppedLastChars = 0L
        while (true) {
            if (pos >= limit) {
                if (ended) return null
                val n = source.read(buf, 0, buf.size)
                if (n < 0) {
                    ended = true
                    skipLf = false
                    if (dropping) return finishDrop()
                    if (line.isNotEmpty()) return take()
                    return null
                }
                pos = 0
                limit = n
                continue
            }
            if (skipLf) {
                skipLf = false
                if (buf[pos] == '\n') {
                    pos++
                    continue
                }
            }
            var i = pos
            while (i < limit) {
                val c = buf[i]
                if (c == '\n' || c == '\r') break
                i++
            }
            val count = i - pos
            if (dropping) {
                droppedChars += count
            } else if (line.length + count > keepMax) {
                droppedChars = (line.length + count).toLong()
                dropping = true
                line = StringBuilder()
            } else {
                line.appendRange(buf, pos, i)
            }
            if (dropping && droppedChars > hardMax) {
                pos = limit
                ended = true
                val chars = droppedChars
                dropping = false
                droppedChars = 0L
                throw LineTooLongException(chars, hardMax)
            }
            if (i < limit) {
                if (buf[i] == '\r') skipLf = true
                pos = i + 1
                return if (dropping) finishDrop() else take()
            }
            pos = limit
        }
    }

    private fun finishDrop(): String {
        droppedLast = true
        droppedLastChars = droppedChars
        dropping = false
        droppedChars = 0L
        return ""
    }

    private fun take(): String {
        val s = line.toString()
        // A big line's buffer is not kept for the next small ones.
        if (line.capacity() > 64 * 1024) line = StringBuilder() else line.setLength(0)
        return s
    }
}
