package org.moonfin.androidtv

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

/**
 * Kos TV: serves the downloaded update APK to the system package installer.
 *
 * A subclass of its own rather than [FileProvider] itself, so the manifest
 * merger can't clash with a plugin that declares the stock class.
 */
class UpdateFileProvider : FileProvider()

/**
 * Kos TV: installs an update APK the app downloaded from its GitHub releases.
 *
 * The flow is driven from Dart (app_update_dialog.dart): it downloads to
 * [downloadPath], makes sure [canInstall] holds (sending the user to
 * [openPermissionSettings] the first time), then calls [install], which hands
 * the file to the system installer. The installer replaces the app only when
 * the APK is signed with the same key, which the release builds are.
 */
object UpdateInstaller {
    private const val DIR = "updates"
    private const val FILE = "kostv-update.apk"
    private const val APK_MIME = "application/vnd.android.package-archive"

    /** Where the update is downloaded. Matches res/xml/update_paths.xml. */
    fun downloadPath(context: Context): String {
        val dir = File(context.cacheDir, DIR).apply { mkdirs() }
        return File(dir, FILE).absolutePath
    }

    /** Whether the user lets this app install packages ("unknown sources"). */
    fun canInstall(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            context.packageManager.canRequestPackageInstalls()

    /**
     * Opens the setting that lets this app install packages: the per-app page
     * where the device has it, the security settings otherwise. False when
     * neither can be opened.
     */
    fun openPermissionSettings(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val perApp = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val security = Intent(Settings.ACTION_SECURITY_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        for (intent in listOf(perApp, security)) {
            try {
                context.startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
            } catch (_: SecurityException) {
            }
        }
        return false
    }

    /**
     * Starts the system installer for the APK at [path], which has to be the
     * file [downloadPath] names. False when it can't be started.
     */
    fun install(context: Context, path: String): Boolean {
        val file = File(path)
        if (!file.isFile || file.canonicalPath != File(downloadPath(context)).canonicalPath) {
            return false
        }
        return try {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.updates",
                file,
            )
            // CLEAR_TASK: the installer's task from the last update is often
            // still there, left on its "App installed" page. With NEW_TASK
            // alone Android just brought that task back, which closed at once,
            // and only a second try reached a fresh installer.
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, APK_MIME)
                .addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TASK,
                )
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }
}
