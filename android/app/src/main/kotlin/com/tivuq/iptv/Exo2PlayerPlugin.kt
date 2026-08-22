package com.tivuq.iptv

import android.app.Activity
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class Exo2PlayerPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        var instance: Exo2PlayerPlugin? = null
        var eventSink: EventChannel.EventSink? = null

    }

    private var texturePlayer: Exo2TexturePlayer? = null
    private var isFrameRateMatchingEnabled = true

    init {
        instance = this
        MethodChannel(messenger, "com.tivuq.iptv/exo2").setMethodCallHandler(this)
        EventChannel(messenger, "com.tivuq.iptv/exo2_events").setStreamHandler(this)
    }

    fun setKeepScreenOn(enabled: Boolean) {
        activity.runOnUiThread {
            if (enabled) {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    fun matchDisplayFrameRate(sourceFps: Float, exactFormat: Boolean = false) {
        if (!isFrameRateMatchingEnabled) return
        (activity as? MainActivity)?.displayRefreshRateManager
            ?.requestContentFrameRate(
                sourceFps,
                stabilizationDelayMs = if (exactFormat) 0L else 900L
            )
    }

    fun isFrameRateMatchingActive(): Boolean = isFrameRateMatchingEnabled

    fun releasePlayerForEngineSwitch() {
        texturePlayer?.dispose()
        texturePlayer = null
    }

    fun pauseForBackground() {
        texturePlayer?.pause()
        setKeepScreenOn(false)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "matchDisplayFrameRate") {
            matchDisplayFrameRate(call.argument<Number>("fps")?.toFloat() ?: 0f)
            result.success(true)
            return
        }
        if (call.method == "setFrameRateMatchingEnabled") {
            isFrameRateMatchingEnabled = call.argument<Boolean>("enabled") ?: true
            Media3PlayerView.isFrameRateMatchingEnabledGlobal = isFrameRateMatchingEnabled
            if (!isFrameRateMatchingEnabled) {
                (activity as? MainActivity)?.displayRefreshRateManager?.restoreImmediately()
            }
            result.success(true)
            return
        }
        if (call.method == "restoreDisplayMode") {
            (activity as? MainActivity)?.displayRefreshRateManager?.restoreImmediately()
            result.success(true)
            return
        }
        if (call.method == "prepareLiveDisplayMode") {
            isFrameRateMatchingEnabled = false
            Media3PlayerView.isFrameRateMatchingEnabledGlobal = false
            val refreshRate = call.argument<Number>("refreshRate")?.toFloat() ?: 50f
            (activity as? MainActivity)?.displayRefreshRateManager
                ?.applyFixedLiveMode(if (refreshRate >= 55f) 60f else 50f)
            result.success(true)
            return
        }
        if (call.method == "getDisplayModeSnapshot") {
            val snapshot = (activity as? MainActivity)?.displayRefreshRateManager?.snapshot()
            result.success(
                mapOf(
                    "displayHz" to (snapshot?.displayHz ?: 60f),
                    "targetHz" to (snapshot?.targetHz ?: 0f),
                    "status" to (snapshot?.status ?: "WAITING")
                )
            )
            return
        }

        when (call.method) {
            "openUrl" -> {
                // A failed Media3 attempt must not leave an additional native
                // video surface below the ExoPlayer2 fallback.
                Media3PlayerView.activeInstance?.dispose()
                val activePlayer = texturePlayer ?: Exo2TexturePlayer(
                    activity
                ).also { texturePlayer = it }
                val httpHeaders = call.argument<Map<String, String>>("httpHeaders").orEmpty()
                activePlayer.openUrl(
                    call.argument<String>("url") ?: "",
                    httpHeaders["User-Agent"]
                        ?: call.argument<String>("userAgent")
                        ?: "IPTVSmartersPlayer",
                    call.argument<String>("quality") ?: "auto",
                    call.argument<Number>("volume")?.toFloat() ?: 1.0f,
                    call.argument<Boolean>("enableTunneling") ?: true,
                    call.argument<Boolean>("diagnosticsEnabled") ?: false,
                    httpHeaders
                )
                result.success(mapOf("directSurface" to true))
            }
            "play" -> { texturePlayer?.play(); result.success(true) }
            "pause" -> { texturePlayer?.pause(); result.success(true) }
            "stop" -> { texturePlayer?.stop(); result.success(true) }
            "seek" -> {
                texturePlayer?.seekTo(call.argument<Number>("positionMs")?.toLong() ?: 0L)
                result.success(true)
            }
            "setVolume" -> {
                texturePlayer?.setVolume(call.argument<Number>("volume")?.toFloat() ?: 1.0f)
                result.success(true)
            }
            "getPlaybackSnapshot" -> result.success(
                texturePlayer?.snapshot() ?: mapOf("positionMs" to 0L, "durationMs" to 0L)
            )
            "getDiagnostics" -> result.success(
                texturePlayer?.diagnostics() ?: mapOf(
                    "engine" to "Native ExoPlayer2 SurfaceView",
                    "frameRateMatchingStatus" to "WAITING"
                )
            )
            "getAudioTracks" -> result.success(
                texturePlayer?.trackOptions(com.google.android.exoplayer2.C.TRACK_TYPE_AUDIO, false)
                    ?: emptyList<Map<String, Any>>()
            )
            "getSubtitleTracks" -> result.success(
                texturePlayer?.trackOptions(com.google.android.exoplayer2.C.TRACK_TYPE_TEXT, true)
                    ?: emptyList<Map<String, Any>>()
            )
            "selectAudioTrack" -> {
                texturePlayer?.selectTrack(
                    com.google.android.exoplayer2.C.TRACK_TYPE_AUDIO,
                    call.argument<String>("id") ?: ""
                )
                result.success(true)
            }
            "selectSubtitleTrack" -> {
                texturePlayer?.selectTrack(
                    com.google.android.exoplayer2.C.TRACK_TYPE_TEXT,
                    call.argument<String>("id") ?: "off"
                )
                result.success(true)
            }
            "dispose" -> {
                releasePlayerForEngineSwitch()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

}
