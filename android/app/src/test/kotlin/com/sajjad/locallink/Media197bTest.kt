package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 197b: small pictures, Save to phone folders, storage percent. */
class Media197bTest {
    @Test
    fun `12 MP photo is decoded small`() {
        val s = MediaStoragePolicy.sampleSize(4000, 3000, 320)
        assertEquals(8, s)
        assertTrue(4000 / s >= 320)
        assertEquals(1, MediaStoragePolicy.sampleSize(300, 200, 320))
        assertEquals(1, MediaStoragePolicy.sampleSize(0, 0, 320))
    }

    @Test
    fun `thumb keeps the shape at 320`() {
        assertEquals(Pair(320, 240), MediaStoragePolicy.scaled(4000, 3000))
        assertEquals(Pair(180, 320), MediaStoragePolicy.scaled(1080, 1920))
        assertEquals(Pair(200, 100), MediaStoragePolicy.scaled(200, 100))
    }

    @Test
    fun `exif rotation`() {
        assertEquals(90, MediaStoragePolicy.exifDegrees(6))
        assertEquals(180, MediaStoragePolicy.exifDegrees(3))
        assertEquals(270, MediaStoragePolicy.exifDegrees(8))
        assertEquals(0, MediaStoragePolicy.exifDegrees(1))
    }

    @Test
    fun `save folders`() {
        assertEquals("Pictures/LinkUp", MediaStoragePolicy.saveFolder("image/jpeg"))
        assertEquals("Pictures/LinkUp", MediaStoragePolicy.saveFolder("video/mp4"))
        assertEquals("Download/LinkUp", MediaStoragePolicy.saveFolder("application/pdf"))
        assertEquals("document", MediaStoragePolicy.saveKind("application/pdf"))
        assertEquals("photo", MediaStoragePolicy.saveKind("IMAGE/PNG"))
    }

    @Test
    fun `safe names`() {
        assertEquals("a.jpg", MediaStoragePolicy.safeName("../../a.jpg"))
        assertEquals("LinkUp_file", MediaStoragePolicy.safeName(".."))
        assertEquals("b_c.pdf", MediaStoragePolicy.safeName("b:c.pdf"))
    }

    @Test
    fun `used percent`() {
        assertEquals(78, MediaStoragePolicy.usedPercent(100, 22))
        assertEquals(0, MediaStoragePolicy.usedPercent(0, 0))
        assertEquals(100, MediaStoragePolicy.usedPercent(100, -5))
    }
}
