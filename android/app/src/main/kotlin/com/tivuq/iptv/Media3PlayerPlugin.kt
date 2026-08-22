package com.tivuq.iptv

import android.app.Activity
import android.os.Build
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.media3.common.util.UnstableApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

@UnstableApi
class Media3PlayerPlugin(
    val activity: Activity,
    private val messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, "com.tivuq.iptv/media3")
    private val eventChannel = EventChannel(messenger, "com.tivuq.iptv/media3_events")

    companion object {
        var instance: Media3PlayerPlugin? = null
        var isKeepScreenOnActive = false
    }

    init {
        instance = this
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    private fun ensurePlayerView(): Media3PlayerView {
        Media3PlayerView.activeInstance?.let { return it }
        // Symmetric native cleanup keeps engine fallback at one video surface,
        // even if Dart disposal and the next open call arrive back-to-back.
        Exo2PlayerPlugin.instance?.releasePlayerForEngineSwitch()
        val view = Media3PlayerView(activity, messenger, -1)
        val content = activity.findViewById<FrameLayout>(android.R.id.content)
        content.addView(
            view.view,
            0,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        return view
    }

    fun setKeepScreenOn(enabled: Boolean) {
        isKeepScreenOnActive = enabled
        activity.runOnUiThread {
            if (enabled) {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "getAndroidApiLevel") {
            result.success(Build.VERSION.SDK_INT)
            return
        }

        if (call.method == "setKeepScreenOn") {
            val enabled = call.argument<Boolean>("enabled") ?: false
            setKeepScreenOn(enabled)
            result.success(true)
            return
        }

        val view = Media3PlayerView.activeInstance
        if (view != null) {
            view.handleMethodCall(call, result)
        } else {
            if (call.method == "getDiagnostics") {
                result.success(mapOf(
                    "engine" to "Native Media3 (Waiting for Surface)",
                    "media3Version" to "1.11.0",
                    "decoderName" to "Unknown",
                    "isHardwareDecoder" to false,
                    "videoMime" to "N/A",
                    "audioMime" to "N/A",
                    "sourceFps" to 0.0f,
                    "displayHz" to 60.0f,
                    "renderedFrames" to 0L,
                    "droppedFrames" to 0L,
                    "bufferDurationMs" to 0L,
                    "rebufferCount" to 0,
                    "startupTimeMs" to 0L,
                    "tunnelingStatus" to false,
                    "asyncCodecQueueing" to false,
                    "keepScreenOnStatus" to isKeepScreenOnActive,
                    "selectedAudioLanguage" to "N/A",
                    "selectedAudioChannels" to 0,
                    "selectedAudioSampleRate" to 0,
                    "positionMs" to 0L,
                    "durationMs" to 0L
                ))
            } else if (call.method == "openUrl") {
                ensurePlayerView().handleMethodCall(call, result)
            } else {
                result.success(null)
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Media3PlayerView.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        Media3PlayerView.eventSink = null
    }
}
