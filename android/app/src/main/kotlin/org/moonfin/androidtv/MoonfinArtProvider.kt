package org.moonfin.androidtv

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * Serves browse artwork to the Android Auto host as content:// URIs.
 *
 * The car host fetches browse icons in its own process, which refuses cleartext
 * http and has no server credentials, so a raw home-server image URL never
 * loads. The Dart browse layer instead hands out content://<app>.artwork/img?u=<url>
 * URIs pointing here; on first read we download the image in the app's own
 * process (cleartext and auth allowed), cache it, and return the file.
 *
 * The provider is exported because audio_service's MediaBrowserService hands the
 * icon URI to the car process without granting it any read permission, so an
 * unexported provider is unreadable there. To keep an exported provider from
 * being an open image proxy, we only fetch http/https URLs whose host is one of
 * the signed-in servers the Dart layer recorded in moonfin_art_hosts.
 *
 * Kos TV: and, since the token is added here, only Jellyfin's image routes get
 * it, and only an image no bigger than [ArtProxyPolicy.MAX_BYTES] is served
 * (see [ArtProxyPolicy]).
 */
class MoonfinArtProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val remote = uri.getQueryParameter("u")
            ?: throw FileNotFoundException("missing url")
        val url = try {
            URL(remote)
        } catch (e: Exception) {
            throw FileNotFoundException("bad url")
        }
        if (url.protocol != "http" && url.protocol != "https") {
            throw FileNotFoundException("unsupported scheme")
        }
        if (url.host !in allowedHosts()) {
            throw FileNotFoundException("host not allowed")
        }
        val ctx = context ?: throw FileNotFoundException("no context")
        val dir = File(ctx.cacheDir, "carart").apply { mkdirs() }
        val file = File(dir, hashName(remote))
        if (!file.exists() || file.length() == 0L) {
            // Kos TV: any other URL (one signed by its server already) is
            // fetched as it is, without the person's token.
            download(if (ArtProxyPolicy.isImagePath(url.path)) withToken(url) else url, file)
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    // shared_preferences stores its keys under the flutter. prefix.
    private fun flutterPref(key: String): String? = context
        ?.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        ?.getString("flutter.$key", null)

    private fun allowedHosts(): Set<String> {
        val raw = flutterPref("moonfin_art_hosts") ?: ""
        return raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
    }

    // The app keeps the server token out of the URI, so it's added back here.
    // URIs saved by older builds still carry it and are left as they are.
    private fun withToken(url: URL): URL {
        val raw = flutterPref("moonfin_art_tokens") ?: return url
        val port = if (url.port == -1) url.defaultPort else url.port
        val token = runCatching {
            JSONObject(raw).optString("${url.protocol}://${url.host.lowercase()}:$port")
        }.getOrNull()
        if (token.isNullOrEmpty()) return url
        val name = token.substringBefore('=')
        val query = url.query
        if (query != null &&
            query.split('&').any { it.substringBefore('=').equals(name, ignoreCase = true) }
        ) {
            return url
        }
        return URL("$url${if (query == null) "?" else "&"}$token")
    }

    private fun download(url: URL, dest: File) {
        val tmp = File.createTempFile("art", ".tmp", dest.parentFile)
        var conn: HttpURLConnection? = null
        try {
            conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 8000
                readTimeout = 8000
                instanceFollowRedirects = true
            }
            // Self-signed trust and client certificates come from the process
            // defaults that moonfin_native_video's TlsPolicy sets.
            if (conn.responseCode !in 200..299) {
                throw FileNotFoundException("http ${conn.responseCode}")
            }
            // Reject non-images (e.g. an HTML login page returned by an auth
            // proxy) so a bogus body is never cached as a permanent broken tile.
            // Kos TV: only an explicit image/* type, before reading the body,
            // so nothing else (a video, a subtitle) is downloaded at all.
            if (!ArtProxyPolicy.isImageType(conn.contentType)) {
                throw FileNotFoundException("not an image")
            }
            if (!ArtProxyPolicy.fitsSize(conn.contentLengthLong)) {
                throw FileNotFoundException("too large")
            }
            conn.inputStream.use { input ->
                tmp.outputStream().use { output -> copyCapped(input, output) }
            }
            // A concurrent read may have already produced the file; keep the
            // first result and drop ours.
            if (!dest.exists() && !tmp.renameTo(dest)) {
                tmp.copyTo(dest, overwrite = true)
            }
        } catch (e: Exception) {
            throw FileNotFoundException(e.message)
        } finally {
            conn?.disconnect()
            if (tmp.exists()) tmp.delete()
        }
    }

    // Kos TV: a body without a length (chunked) is cut off at the cap too.
    private fun copyCapped(input: InputStream, output: OutputStream) {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val n = input.read(buffer)
            if (n < 0) return
            total += n
            if (!ArtProxyPolicy.fitsSize(total)) throw FileNotFoundException("too large")
            output.write(buffer, 0, n)
        }
    }

    private fun hashName(value: String): String {
        val digest = MessageDigest.getInstance("SHA-1").digest(value.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    override fun getType(uri: Uri): String = "image/*"

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}
