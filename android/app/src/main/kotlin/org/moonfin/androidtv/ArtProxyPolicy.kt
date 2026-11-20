package org.moonfin.androidtv

/**
 * Kos TV: what [MoonfinArtProvider] agrees to fetch, kept free of the
 * Android runtime so plain JVM tests cover it.
 *
 * The provider is exported, so any app on the device can ask it for a URL.
 * The signed-in person's token is only ever added to the Jellyfin image
 * routes the app wraps (an item's images and a user's avatar, as
 * JellyfinImageApi builds them), and whatever comes back has to be a
 * reasonably sized image, so it can't be used to download a video, a
 * subtitle or the API's answers with the person's token.
 */
internal object ArtProxyPolicy {
    /** Far above any poster or backdrop the app asks for. */
    const val MAX_BYTES = 20L * 1024 * 1024

    // An optional base path (a server behind /jellyfin), then
    // /Items/{id}/Images/{type}[/{index}] or /Users/{id}/Images/{type}.
    // Segments can't start with a dot and nothing is percent-encoded, so
    // "..", "%2e" or "%2f" can't walk out of an image route.
    private val IMAGE_PATH = Regex(
        "^(?:/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)*" +
            "/(?:Items|Users)/[A-Za-z0-9-]+/Images/[A-Za-z]+(?:/[0-9]+)?/?$",
        RegexOption.IGNORE_CASE,
    )

    /** Whether [path] (the raw, undecoded URL path) is a Jellyfin image. */
    fun isImagePath(path: String?): Boolean =
        path != null && IMAGE_PATH.matches(path)

    /** Only an explicit image content type is served. */
    fun isImageType(contentType: String?): Boolean {
        val ct = contentType?.substringBefore(';')?.trim()?.lowercase()
        return ct != null && ct.startsWith("image/") && ct.length > "image/".length
    }

    /** Whether a body of [length] bytes (-1 when unknown) may be kept. */
    fun fitsSize(length: Long): Boolean = length <= MAX_BYTES
}
