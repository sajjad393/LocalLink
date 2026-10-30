package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 169 (4.3): the background engine after a reboot. */
class Boot169Test {
    private fun skip(
        bootOk: Boolean = true,
        appOpen: Boolean = false,
        running: Boolean = false,
        opened: Long = 69,
        current: Long = 69,
    ) = BackgroundEnginePolicy.skipReason(bootOk, appOpen, running, opened, current)

    @Test fun `starts after a good boot on a version that was opened`() {
        assertNull(skip())
    }

    @Test fun `never starts when the service itself could not start`() {
        assertEquals("service_not_started", skip(bootOk = false))
    }

    @Test fun `never runs next to the open app`() {
        assertEquals("app_open", skip(appOpen = true))
    }

    @Test fun `never starts twice`() {
        assertEquals("running", skip(running = true))
    }

    @Test fun `never starts on a phone where the app was never opened`() {
        assertEquals("never_opened", skip(opened = 0))
    }

    @Test fun `a new version waits until the app is opened once`() {
        assertEquals("new_version_not_opened", skip(opened = 68, current = 69))
    }

    @Test fun `the tap to reconnect notice shows only when messages would not arrive`() {
        assertTrue(BackgroundEnginePolicy.showReconnectNotice("error"))
        assertTrue(BackgroundEnginePolicy.showReconnectNotice("new_version_not_opened"))
        assertFalse(BackgroundEnginePolicy.showReconnectNotice(null))
        assertFalse(BackgroundEnginePolicy.showReconnectNotice("posted"))
        assertFalse(BackgroundEnginePolicy.showReconnectNotice("never_opened"))
        assertFalse(BackgroundEnginePolicy.showReconnectNotice("app_open"))
    }
}
