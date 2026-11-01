package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class File193Test {
    private val sha = "abcdef0123456789".repeat(4)

    @Test fun src_kinds() {
        assertEquals("staged", FileSendLogPolicy.srcKind("/data/user/0/com.sajjad.linkup/databases/attachments/outbox-f1.mp4"))
        assertEquals("view", FileSendLogPolicy.srcKind("/data/user/0/x/databases/attachments/views/.view-123.mp4"))
        assertEquals("locked", FileSendLogPolicy.srcKind("/data/x/attachments/outbox-f1.mp4.enc"))
        assertEquals("received", FileSendLogPolicy.srcKind("/data/x/files/locallink_direct_files/t1_a.mp4"))
        assertEquals("picker", FileSendLogPolicy.srcKind("/data/x/cache/image_picker123.mp4"))
        assertEquals("other", FileSendLogPolicy.srcKind("/sdcard/DCIM/a.mp4"))
        assertEquals("-", FileSendLogPolicy.srcKind(null))
        assertEquals("-", FileSendLogPolicy.srcKind("  "))
    }

    @Test fun send_start_line() {
        val l = FileSendLogPolicy.sendStart("transfer-0123456789", "transfer-0123456789", 13_000_000, sha, 199, 0, false, true, "/d/attachments/outbox-x.mp4")
        assertEquals("FILE_SEND_START transfer=transfer-012 file=transfer-012 size=13000000 sha=abcdef01 chunks=199 done=0 reuse=n busy=y src=staged", l)
    }

    @Test fun replaced_line_shows_both_versions() {
        val l = FileSendLogPolicy.sendReplaced("t1", 13_000_000, sha, 40, "/d/attachments/.view-1.mp4", 13_000_000, sha, "/d/attachments/.view-2.mp4")
        assertTrue(l.startsWith("FILE_SEND_REPLACED transfer=t1 "))
        assertTrue(l.contains(" old_done=40 old_src=view "))
        assertTrue(l.endsWith(" new_sha=abcdef01 new_src=view"))
    }

    @Test fun source_problem_reasons() {
        assertEquals("missing", FileSendLogPolicy.sourceProblem(false, -1, 10) { true })
        assertEquals("size_changed", FileSendLogPolicy.sourceProblem(true, 5, 10) { true })
        assertEquals("content_changed", FileSendLogPolicy.sourceProblem(true, 10, 10) { false })
        assertNull(FileSendLogPolicy.sourceProblem(true, 10, 10) { true })
    }

    @Test fun sha_not_read_when_size_differs() {
        var asked = false
        FileSendLogPolicy.sourceProblem(true, 5, 10) { asked = true; true }
        assertEquals(false, asked)
    }

    @Test fun receive_lines() {
        assertEquals("FILE_RECEIVE_START transfer=t1 size=10 sha=abcdef01 chunks=1 resumed=y have=0",
            FileSendLogPolicy.receiveStart("t1", 10, sha, 1, true, 0))
        assertEquals("FILE_RECEIVED_OK transfer=t1 size=10 sha=abcdef01 chunks=1",
            FileSendLogPolicy.receivedOk("t1", 10, sha, 1))
        assertEquals("FILE_SEND_DONE transfer=t1 size=10 sha=abcdef01 chunks=1",
            FileSendLogPolicy.sendDone("t1", 10, sha, 1))
        assertTrue(FileSendLogPolicy.chunkIgnored("t1", 10, sha, 11, "0000000011112222").endsWith("got_size=11 got_sha=00000000"))
    }

    @Test fun restore_lines() {
        assertEquals("FILE_SEND_RESTORED transfer=t1 size=10 sha=abcdef01 done=3/5 src=staged",
            FileSendLogPolicy.restored("t1", 10, sha, 3, 5, "/a/attachments/outbox-1.bin"))
        assertEquals("FILE_SEND_RESTORE_DROPPED transfer=t1 reason=idle", FileSendLogPolicy.restoreDropped("t1", "idle"))
        assertEquals("FILE_SEND_SOURCE_BAD transfer=t1 reason=missing size=10 now=-1 src=view",
            FileSendLogPolicy.sourceBad("t1", "missing", 10, -1, "/a/.view-9.mp4"))
    }

    @Test fun empty_ids_are_dash() {
        assertEquals("-", FileSendLogPolicy.id(""))
        assertEquals("-", FileSendLogPolicy.sha(null))
    }
}
