package org.moonfin.androidtv

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.provider.Settings
import java.io.ByteArrayOutputStream

/**
 * Kos TV: the apps installed on the TV, for the Apps row on Home and the
 * All apps screen. Lists what the TV's own launcher would show (activities in
 * LEANBACK_LAUNCHER; LAUNCHER on a phone, or on a TV box without leanback
 * apps), each with its TV banner, or its icon when it has none, as PNG bytes.
 */
object InstalledApps {
    /** Banners are 320x180 dp; rendered at 2x so they stay sharp at 1080p. */
    private const val BANNER_WIDTH = 640
    private const val BANNER_HEIGHT = 360
    private const val ICON_SIZE = 192

    fun list(context: Context): List<Map<String, Any?>> {
        val pm = context.packageManager
        val leanback = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        var infos = if (leanback) query(pm, Intent.CATEGORY_LEANBACK_LAUNCHER) else emptyList()
        if (infos.isEmpty()) infos = query(pm, Intent.CATEGORY_LAUNCHER)

        // The TV's own Settings app: All apps opens it from its first card,
        // so it isn't listed a second time.
        val settings = SETTINGS_PACKAGES + listOfNotNull(settingsPackage(pm))
        val seen = HashSet<String>()
        return infos
            .mapNotNull { info ->
                val activity = info.activityInfo ?: return@mapNotNull null
                val pkg = activity.packageName
                if (pkg == context.packageName || pkg in settings || !seen.add(pkg)) {
                    return@mapNotNull null
                }
                val label = info.loadLabel(pm)?.toString()?.trim().orEmpty().ifEmpty { pkg }
                val banner = runCatching { activity.loadBanner(pm) }.getOrNull()
                val art = if (banner != null) {
                    toPng(banner, BANNER_WIDTH, BANNER_HEIGHT)
                } else {
                    runCatching { info.loadIcon(pm) }.getOrNull()?.let { toPng(it, ICON_SIZE, ICON_SIZE) }
                }
                mapOf(
                    "package" to pkg,
                    "label" to label,
                    "art" to art,
                    "isBanner" to (banner != null && art != null),
                )
            }
            .sortedBy { (it["label"] as String).lowercase() }
    }

    /** Opens [pkg] the way the TV launcher would. False if it can't be opened. */
    fun launch(context: Context, pkg: String): Boolean {
        val pm = context.packageManager
        val intent = pm.getLeanbackLaunchIntentForPackage(pkg)
            ?: pm.getLaunchIntentForPackage(pkg)
            ?: return false
        return start(context, intent)
    }

    /** Opens the TV's own settings. */
    fun openSystemSettings(context: Context): Boolean =
        start(context, Intent(Settings.ACTION_SETTINGS))

    private fun start(context: Context, intent: Intent): Boolean = try {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }

    /** The usual packages of the TV's Settings app. */
    private val SETTINGS_PACKAGES = setOf("com.android.tv.settings", "com.android.settings")

    /** The app that opens for the system settings on this TV, if it can be told. */
    private fun settingsPackage(pm: PackageManager): String? = runCatching {
        val intent = Intent(Settings.ACTION_SETTINGS)
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.resolveActivity(
                intent,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        }
        // "android" is the chooser, when more than one app claims it.
        info?.activityInfo?.packageName?.takeIf { it != "android" }
    }.getOrNull()

    private fun query(pm: PackageManager, category: String): List<ResolveInfo> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(category)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
    }

    /** Draws [drawable] into a bitmap no bigger than [maxWidth] x [maxHeight]. */
    private fun toPng(drawable: Drawable, maxWidth: Int, maxHeight: Int): ByteArray? = try {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            val source = drawable.bitmap
            val scale = minOf(1f, maxWidth / source.width.toFloat(), maxHeight / source.height.toFloat())
            if (scale < 1f) {
                Bitmap.createScaledBitmap(
                    source,
                    (source.width * scale).toInt().coerceAtLeast(1),
                    (source.height * scale).toInt().coerceAtLeast(1),
                    true,
                )
            } else {
                source
            }
        } else {
            val w = drawable.intrinsicWidth.takeIf { it > 0 } ?: maxWidth
            val h = drawable.intrinsicHeight.takeIf { it > 0 } ?: maxHeight
            val scale = minOf(maxWidth / w.toFloat(), maxHeight / h.toFloat())
            val width = (w * scale).toInt().coerceAtLeast(1)
            val height = (h * scale).toInt().coerceAtLeast(1)
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                val canvas = Canvas(it)
                drawable.setBounds(0, 0, width, height)
                drawable.draw(canvas)
            }
        }
        ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    } catch (_: Throwable) {
        null
    }
}
