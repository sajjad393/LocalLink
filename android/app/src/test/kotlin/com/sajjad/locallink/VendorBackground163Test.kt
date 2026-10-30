package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VendorBackground163Test {
    @Test
    fun `every named brand has at least one page and other falls back to app info`() {
        for (brand in VendorBackgroundIntents.BRANDS) {
            val pages = VendorBackgroundIntents.candidates(brand)
            if (brand == "other") assertTrue(pages.isEmpty()) else assertTrue(brand, pages.isNotEmpty())
        }
        assertTrue(VendorBackgroundIntents.candidates("unknown").isEmpty())
    }

    @Test
    fun `brand key is case insensitive and keeps the old Xiaomi and Transsion pages`() {
        assertEquals(VendorBackgroundIntents.candidates("xiaomi"), VendorBackgroundIntents.candidates("XIAOMI"))
        assertEquals("com.miui.securitycenter", VendorBackgroundIntents.candidates("xiaomi").first().first)
        assertEquals("com.transsion.phonemanager", VendorBackgroundIntents.candidates("transsion").first().first)
    }
}
