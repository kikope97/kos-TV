package org.moonfin.androidtv

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ArtProxyPolicyTest {
    @Test
    fun `the image routes the app wraps get the token`() {
        for (path in listOf(
            "/Items/0123abcd/Images/Primary",
            "/Items/0123abcd/Images/Backdrop/0",
            "/Items/0123abcd/Images/Thumb",
            "/Items/0123abcd/Images/Logo",
            "/Items/0123abcd/Images/Chapter/3",
            "/Users/0123abcd/Images/Primary",
            "/jellyfin/Items/0123abcd/Images/Primary",
            "/items/0123abcd/images/primary",
        )) {
            assertTrue(path, ArtProxyPolicy.isImagePath(path))
        }
    }

    @Test
    fun `anything else does not`() {
        for (path in listOf(
            null,
            "",
            "/Items/0123abcd/Download",
            "/Videos/0123abcd/stream",
            "/Videos/0123abcd/0123abcd/Subtitles/0/Stream.srt",
            "/Items/0123abcd/Images",
            "/Items/0123abcd/Images/Primary/../../Download",
            "/Items/0123abcd/Images/Primary/0/../../../Download",
            "/../Items/0123abcd/Images/Primary",
            "/Items/0123abcd/Images/Primary%2F..%2F..%2FDownload",
            "/Items/%2e%2e/Images/Primary",
            "/Users/0123abcd/Items",
            "/Persons/Someone/Images/Primary",
        )) {
            assertFalse("$path", ArtProxyPolicy.isImagePath(path))
        }
    }

    @Test
    fun `only an image content type is served`() {
        assertTrue(ArtProxyPolicy.isImageType("image/jpeg"))
        assertTrue(ArtProxyPolicy.isImageType("Image/WEBP; charset=binary"))
        for (type in listOf(null, "", "image/", "video/mp4", "text/html",
            "application/json", "application/octet-stream", "application/x-subrip")) {
            assertFalse("$type", ArtProxyPolicy.isImageType(type))
        }
    }

    @Test
    fun `a body past the cap is refused`() {
        assertTrue(ArtProxyPolicy.fitsSize(-1))
        assertTrue(ArtProxyPolicy.fitsSize(ArtProxyPolicy.MAX_BYTES))
        assertFalse(ArtProxyPolicy.fitsSize(ArtProxyPolicy.MAX_BYTES + 1))
    }
}
