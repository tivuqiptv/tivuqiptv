package com.tivuq.iptv

import android.content.Context
import android.util.Log
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import com.google.android.exoplayer2.C
import com.google.android.exoplayer2.DefaultLoadControl
import com.google.android.exoplayer2.DefaultRenderersFactory
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.Format
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.PlaybackException
import com.google.android.exoplayer2.Player
import com.google.android.exoplayer2.Tracks
import com.google.android.exoplayer2.RendererCapabilities
import com.google.android.exoplayer2.audio.AudioAttributes
import com.google.android.exoplayer2.analytics.AnalyticsListener
import com.google.android.exoplayer2.decoder.DecoderReuseEvaluation
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.source.hls.HlsMediaSource
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.util.ArrayDeque
import kotlin.math.abs

class Exo2PlayerView(
    private val context: Context,
    messenger: BinaryMessenger
) : PlatformView {
    companion object {
        var activeInstance: Exo2PlayerView? = null
        var pendingOpen: Map<String, Any>? = null
    }

    private val rootView = FrameLayout(context)
    private val surfaceView = SurfaceView(context)
    private val trackSelector = DefaultTrackSelector(context)
    private val player: ExoPlayer
    private val initialPresentationTimestampsUs = ArrayDeque<Long>()
    private var frameRateMatchCommitted = false

    init {
        activeInstance = this
        rootView.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        val renderersFactory = DefaultRenderersFactory(context)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(15000, 50000, 2500, 5000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        player = ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .build()
        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            true
        )
        player.setVideoSurfaceView(surfaceView)
        player.setVideoFrameMetadataListener { presentationTimeUs, _, _, _ ->
            synchronized(initialPresentationTimestampsUs) {
                if (frameRateMatchCommitted) return@setVideoFrameMetadataListener
                initialPresentationTimestampsUs.addLast(presentationTimeUs)
                if (initialPresentationTimestampsUs.size >= 50) {
                    val deltas = initialPresentationTimestampsUs.toList()
                        .zipWithNext { first, second -> second - first }
                        .filter { it in 5_000L..100_000L }
                        .sorted()
                    if (deltas.size >= 35) {
                        val measuredFps =
                            1_000_000f / deltas[deltas.size / 2].toFloat()
                        val standards = floatArrayOf(
                            23.976f, 24f, 25f, 29.97f, 30f, 50f, 59.94f, 60f
                        )
                        val matchedFps = standards.minByOrNull {
                            abs(it - measuredFps)
                        } ?: measuredFps
                        if (abs(matchedFps - measuredFps) < 0.8f) {
                            frameRateMatchCommitted = true
                            Exo2PlayerPlugin.instance?.matchDisplayFrameRate(matchedFps)
                        }
                    }
                    if (initialPresentationTimestampsUs.size >= 80) {
                        frameRateMatchCommitted = true
                    }
                }
            }
        }
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                sendEvent(
                    "onPlaybackState",
                    mapOf(
                        "state" to state,
                        "isBuffering" to (state == Player.STATE_BUFFERING),
                        "isEnded" to (state == Player.STATE_ENDED)
                    )
                )
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                sendEvent("onIsPlayingChanged", mapOf("isPlaying" to isPlaying))
                Exo2PlayerPlugin.instance?.setKeepScreenOn(isPlaying)
            }

            override fun onPlayerError(error: PlaybackException) {
                sendEvent(
                    "onError",
                    mapOf("errorMessage" to (error.message ?: "ExoPlayer2 playback error"))
                )
            }

            override fun onTracksChanged(tracks: Tracks) {
                var audioSelected = false
                var hasAudio = false
                var hasSupportedAudio = false
                val audioFormats = mutableListOf<String>()
                for (group in tracks.groups) {
                    if (group.type != C.TRACK_TYPE_AUDIO) continue
                    hasAudio = true
                    if (group.isSupported) hasSupportedAudio = true
                    if (group.isSelected) audioSelected = true
                    for (index in 0 until group.length) {
                        val format = group.getTrackFormat(index)
                        audioFormats.add(
                            "${format.sampleMimeType ?: "unknown"}/" +
                                "${format.codecs ?: "unknown"}:" +
                                "supported=${group.isTrackSupported(index)}," +
                                "selected=${group.isTrackSelected(index)}"
                        )
                    }
                }

                Log.i(
                    "TivuqAudioTracks",
                    if (audioFormats.isEmpty()) "NO_AUDIO_TRACK" else audioFormats.joinToString(";")
                )

                sendEvent(
                    "onAudioTracksChanged",
                    mapOf(
                        "hasAudio" to hasAudio,
                        "hasSupportedAudio" to hasSupportedAudio,
                        "formats" to audioFormats
                    )
                )

                if (!audioSelected) {
                    forceFirstSupportedAudioTrack()
                }
            }
        })

        player.addAnalyticsListener(object : AnalyticsListener {
            override fun onVideoInputFormatChanged(
                eventTime: AnalyticsListener.EventTime,
                format: Format,
                decoderReuseEvaluation: DecoderReuseEvaluation?
            ) {
                if (format.frameRate > 0f) {
                    frameRateMatchCommitted = true
                    Exo2PlayerPlugin.instance?.matchDisplayFrameRate(
                        format.frameRate,
                        exactFormat = true
                    )
                }
            }
        })

        pendingOpen?.let { pending ->
            openUrl(
                pending["url"] as? String ?: "",
                pending["userAgent"] as? String ?: "IPTVSmartersPlayer",
                pending["quality"] as? String ?: "auto",
                pending["volume"] as? Float ?: 1.0f
            )
            pendingOpen = null
        }
    }

    private fun openUrl(url: String, userAgent: String, quality: String, volume: Float) {
        if (url.isBlank()) return
        synchronized(initialPresentationTimestampsUs) {
            initialPresentationTimestampsUs.clear()
            frameRateMatchCommitted = false
        }
        applyQuality(quality)
        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(15000)
            .setAllowCrossProtocolRedirects(true)
        val item = MediaItem.fromUri(url)
        val lowerUrl = url.lowercase()
        val source = if (lowerUrl.contains(".m3u8") || lowerUrl.contains("type=m3u8")) {
            HlsMediaSource.Factory(dataSourceFactory).createMediaSource(item)
        } else {
            ProgressiveMediaSource.Factory(dataSourceFactory).createMediaSource(item)
        }
        player.setMediaSource(source)
        player.volume = volume.coerceIn(0.0f, 1.0f)
        player.prepare()
        player.playWhenReady = true
        Exo2PlayerPlugin.instance?.setKeepScreenOn(true)
    }

    private fun applyQuality(quality: String) {
        val (maxWidth, maxHeight) = when (quality.lowercase()) {
            "720p" -> 1280 to 720
            "1080p" -> 1920 to 1080
            "4k" -> 3840 to 2160
            else -> Int.MAX_VALUE to Int.MAX_VALUE
        }
        trackSelector.setParameters(
            trackSelector.buildUponParameters().setMaxVideoSize(maxWidth, maxHeight)
        )
    }

    private fun forceFirstSupportedAudioTrack() {
        val mappedInfo = trackSelector.currentMappedTrackInfo ?: return
        for (rendererIndex in 0 until mappedInfo.rendererCount) {
            if (mappedInfo.getRendererType(rendererIndex) != C.TRACK_TYPE_AUDIO) continue
            val groups = mappedInfo.getTrackGroups(rendererIndex)
            for (groupIndex in 0 until groups.length) {
                val group = groups[groupIndex]
                for (trackIndex in 0 until group.length) {
                    if (mappedInfo.getTrackSupport(rendererIndex, groupIndex, trackIndex) ==
                        RendererCapabilities.FORMAT_HANDLED
                    ) {
                        val override = DefaultTrackSelector.SelectionOverride(
                            groupIndex,
                            trackIndex
                        )
                        trackSelector.setParameters(
                            trackSelector.buildUponParameters()
                                .setSelectionOverride(rendererIndex, groups, override)
                        )
                        return
                    }
                }
            }
        }
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openUrl" -> {
                openUrl(
                    call.argument<String>("url") ?: "",
                    call.argument<String>("userAgent") ?: "IPTVSmartersPlayer",
                    call.argument<String>("quality") ?: "auto",
                    call.argument<Number>("volume")?.toFloat() ?: 1.0f
                )
                result.success(true)
            }
            "play" -> { player.play(); result.success(true) }
            "pause" -> { player.pause(); result.success(true) }
            "stop" -> { player.stop(); result.success(true) }
            "seek" -> {
                player.seekTo(call.argument<Number>("positionMs")?.toLong() ?: 0L)
                result.success(true)
            }
            "setVolume" -> {
                player.volume = (call.argument<Number>("volume")?.toFloat() ?: 1.0f)
                    .coerceIn(0.0f, 1.0f)
                result.success(true)
            }
            "getPlaybackSnapshot" -> result.success(
                mapOf(
                    "positionMs" to player.currentPosition,
                    "durationMs" to player.duration
                )
            )
            else -> result.notImplemented()
        }
    }

    private fun sendEvent(type: String, data: Map<String, Any>) {
        val payload = HashMap(data)
        payload["event"] = type
        rootView.post { Exo2PlayerPlugin.eventSink?.success(payload) }
    }

    override fun getView(): View = rootView

    override fun dispose() {
        if (activeInstance == this) activeInstance = null
        Exo2PlayerPlugin.instance?.setKeepScreenOn(false)
        player.clearVideoSurfaceView(surfaceView)
        player.release()
    }
}
