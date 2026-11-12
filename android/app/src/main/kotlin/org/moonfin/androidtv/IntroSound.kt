package org.moonfin.androidtv

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log
import io.flutter.FlutterInjector
import java.io.File

/**
 * Kos TV: plays the sound of the opening animation, a short track among the
 * app's Flutter assets, with the system's MediaPlayer. It has nothing to load
 * but the track, so it starts with the first frames on any TV.
 */
object IntroSound {
    private const val TAG = "KosIntroSound"
    private var player: MediaPlayer? = null

    /** Starts [asset]; [onStarted] is called once, with whether it is playing. */
    fun play(context: Context, asset: String, onStarted: (Boolean) -> Unit) {
        var answered = false
        fun answer(started: Boolean) {
            if (answered) return
            answered = true
            onStarted(started)
        }
        stop()
        try {
            val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
            val mp = MediaPlayer()
            player = mp
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            setSource(context, mp, key)
            mp.setOnPreparedListener {
                try {
                    it.start()
                    answer(true)
                } catch (e: Exception) {
                    Log.w(TAG, "start failed", e)
                    answer(false)
                }
            }
            mp.setOnErrorListener { _, what, extra ->
                Log.w(TAG, "player error $what/$extra")
                stop()
                answer(false)
                true
            }
            mp.setOnCompletionListener { stop() }
            mp.prepareAsync()
        } catch (e: Exception) {
            Log.w(TAG, "could not play $asset", e)
            stop()
            answer(false)
        }
    }

    /**
     * Straight from the APK when the asset is stored as it is; from a copy in
     * the cache when the build compressed it.
     */
    private fun setSource(context: Context, mp: MediaPlayer, key: String) {
        try {
            context.assets.openFd(key).use { fd ->
                mp.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
            }
        } catch (e: Exception) {
            val copy = File(context.cacheDir, "kostv_intro_sound")
            context.assets.open(key).use { input ->
                copy.outputStream().use { output -> input.copyTo(output) }
            }
            mp.setDataSource(copy.absolutePath)
        }
    }

    fun stop() {
        val mp = player ?: return
        player = null
        try {
            mp.release()
        } catch (e: Exception) {
            Log.w(TAG, "release failed", e)
        }
    }
}
