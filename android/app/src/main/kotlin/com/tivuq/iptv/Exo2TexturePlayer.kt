package com.tivuq.iptv

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.util.Log
import android.view.SurfaceView
import android.widget.FrameLayout
import com.google.android.exoplayer2.C
import com.google.android.exoplayer2.DefaultLoadControl
import com.google.android.exoplayer2.DefaultRenderersFactory
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.Format
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.PlaybackException
import com.google.android.exoplayer2.Player
import com.google.android.exoplayer2.RendererCapabilities
import com.google.android.exoplayer2.Tracks
import com.google.android.exoplayer2.analytics.AnalyticsListener
import com.google.android.exoplayer2.audio.AudioAttributes
import com.google.android.exoplayer2.decoder.DecoderReuseEvaluation
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.source.hls.HlsMediaSource
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import java.util.ArrayDeque
import kotlin.math.abs

class Exo2TexturePlayer(
    private val activity: Activity
) {
    private val videoHost = FrameLayout(activity).apply {
        setBackgroundColor(Color.BLACK)
    }
    private val surfaceView = SurfaceView(activity)
    private val trackSelector = DefaultTrackSelector(activity)
    private val player: ExoPlayer
    private val initialTimestampsUs = ArrayDeque<Long>()
    private val releaseDeltasNs = ArrayDeque<Long>()
    private var lastReleaseTimeNs = 0L
    private var frameRateMatchCommitted = false
    private var sourceFps = 0f
    private var decoderName = "Unknown"
    private var isHardwareDecoder = false
    private var rebufferCount = 0
    private var startupTimeMs = 0L
    private var playRequestedTimeMs = 0L
    private var pacingMedianMs = 0.0
    private var pacingP95Ms = 0.0
    private var lastPlaybackError = "None"
    private var diagnosticsEnabled = false

    init {
        val content = activity.findViewById<FrameLayout>(android.R.id.content)
        videoHost.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        content.addView(
            videoHost,
            0,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        val renderersFactory = DefaultRenderersFactory(activity)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(15000, 50000, 2500, 5000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        player = ExoPlayer.Builder(activity, renderersFactory)
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

        player.setVideoFrameMetadataListener { presentationTimeUs, releaseTimeNs, _, _ ->
            if (diagnosticsEnabled && lastReleaseTimeNs > 0L) {
                val delta = releaseTimeNs - lastReleaseTimeNs
                if (delta in 1_000_000L..100_000_000L) {
                    releaseDeltasNs.addLast(delta)
                    if (releaseDeltasNs.size >= 250) {
                        val sorted = releaseDeltasNs.sorted()
                        val medianMs = sorted[sorted.size / 2] / 1_000_000.0
                        val p95Ms = sorted[(sorted.size * 95 / 100)
                            .coerceAtMost(sorted.lastIndex)] / 1_000_000.0
                        val minMs = sorted.first() / 1_000_000.0
                        val maxMs = sorted.last() / 1_000_000.0
                        pacingMedianMs = medianMs
                        pacingP95Ms = p95Ms
                        Log.i(
                            "TivuqPacing",
                            "releaseDeltaMs min=$minMs median=$medianMs p95=$p95Ms max=$maxMs"
                        )
                        releaseDeltasNs.clear()
                    }
                }
            }
            if (diagnosticsEnabled) lastReleaseTimeNs = releaseTimeNs
            if (Exo2PlayerPlugin.instance?.isFrameRateMatchingActive() != true) {
                return@setVideoFrameMetadataListener
            }
            synchronized(initialTimestampsUs) {
                if (frameRateMatchCommitted) return@setVideoFrameMetadataListener
                initialTimestampsUs.addLast(presentationTimeUs)
                if (initialTimestampsUs.size >= 50) {
                    val deltas = initialTimestampsUs.toList()
                        .zipWithNext { first, second -> second - first }
                        .filter { it in 5_000L..100_000L }
                        .sorted()
                    if (deltas.size >= 35) {
                        val measuredFps = 1_000_000f / deltas[deltas.size / 2].toFloat()
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
                    if (initialTimestampsUs.size >= 80) {
                        frameRateMatchCommitted = true
                    }
                }
            }
        }

        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_BUFFERING) rebufferCount++
                if (state == Player.STATE_READY && playRequestedTimeMs > 0L) {
                    startupTimeMs = System.currentTimeMillis() - playRequestedTimeMs
                    playRequestedTimeMs = 0L
                }
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
                lastPlaybackError = error.message ?: "ExoPlayer2 playback error"
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
                if (!audioSelected) forceFirstSupportedAudioTrack()
            }
        })

        player.addAnalyticsListener(object : AnalyticsListener {
            override fun onVideoDecoderInitialized(
                eventTime: AnalyticsListener.EventTime,
                decoderName: String,
                initializedTimestampMs: Long,
                initializationDurationMs: Long
            ) {
                this@Exo2TexturePlayer.decoderName = decoderName
                val lower = decoderName.lowercase()
                isHardwareDecoder = !lower.contains("omx.google") &&
                    !lower.contains("c2.android") &&
                    !lower.contains(".sw.") &&
                    !lower.startsWith("omx.ffmpeg")
            }

            override fun onVideoInputFormatChanged(
                eventTime: AnalyticsListener.EventTime,
                format: Format,
                decoderReuseEvaluation: DecoderReuseEvaluation?
            ) {
                if (format.frameRate > 0f) {
                    sourceFps = format.frameRate
                    frameRateMatchCommitted = true
                    Exo2PlayerPlugin.instance?.matchDisplayFrameRate(
                        format.frameRate,
                        exactFormat = true
                    )
                }
            }
        })
    }

    fun openUrl(
        url: String,
        userAgent: String,
        quality: String,
        volume: Float,
        enableTunneling: Boolean,
        diagnosticsEnabled: Boolean,
        httpHeaders: Map<String, String>
    ) {
        if (url.isBlank()) return
        this.diagnosticsEnabled = diagnosticsEnabled
        playRequestedTimeMs = System.currentTimeMillis()
        rebufferCount = 0
        startupTimeMs = 0L
        pacingMedianMs = 0.0
        pacingP95Ms = 0.0
        lastPlaybackError = "None"
        sourceFps = 0f
        synchronized(initialTimestampsUs) {
            initialTimestampsUs.clear()
            frameRateMatchCommitted = false
        }
        releaseDeltasNs.clear()
        lastReleaseTimeNs = 0L
        applyPlaybackParameters(quality, enableTunneling)
        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(15000)
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(httpHeaders)
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

    private fun applyPlaybackParameters(quality: String, enableTunneling: Boolean) {
        val (maxWidth, maxHeight) = when (quality.lowercase()) {
            "720p" -> 1280 to 720
            "1080p" -> 1920 to 1080
            "4k" -> 3840 to 2160
            else -> Int.MAX_VALUE to Int.MAX_VALUE
        }
        trackSelector.setParameters(
            trackSelector.buildUponParameters()
                .setMaxVideoSize(maxWidth, maxHeight)
                .setTunnelingEnabled(enableTunneling)
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
                        trackSelector.setParameters(
                            trackSelector.buildUponParameters().setSelectionOverride(
                                rendererIndex,
                                groups,
                                DefaultTrackSelector.SelectionOverride(groupIndex, trackIndex)
                            )
                        )
                        return
                    }
                }
            }
        }
    }

    fun play() = player.play()
    fun pause() = player.pause()
    fun stop() = player.stop()
    fun seekTo(positionMs: Long) = player.seekTo(positionMs)
    fun setVolume(volume: Float) { player.volume = volume.coerceIn(0.0f, 1.0f) }

    fun trackOptions(trackType: Int, includeOff: Boolean): List<Map<String, Any>> {
        val mappedInfo = trackSelector.currentMappedTrackInfo ?: return emptyList()
        val result = mutableListOf<Map<String, Any>>()
        if (includeOff) {
            var disabled = player.currentTracks.groups.none {
                it.type == trackType && it.isSelected
            }
            for (rendererIndex in 0 until mappedInfo.rendererCount) {
                if (mappedInfo.getRendererType(rendererIndex) == trackType &&
                    trackSelector.parameters.getRendererDisabled(rendererIndex)
                ) {
                    disabled = true
                }
            }
            result.add(mapOf(
                "id" to "off",
                "label" to "Off",
                "language" to "",
                "isSelected" to disabled,
                "isOff" to true
            ))
        }
        for (rendererIndex in 0 until mappedInfo.rendererCount) {
            if (mappedInfo.getRendererType(rendererIndex) != trackType) continue
            val groups = mappedInfo.getTrackGroups(rendererIndex)
            for (groupIndex in 0 until groups.length) {
                val group = groups[groupIndex]
                val currentGroup = player.currentTracks.groups.firstOrNull {
                    it.mediaTrackGroup == group
                }
                for (trackIndex in 0 until group.length) {
                    if (mappedInfo.getTrackSupport(rendererIndex, groupIndex, trackIndex) !=
                        RendererCapabilities.FORMAT_HANDLED
                    ) continue
                    val format = group.getFormat(trackIndex)
                    val fallback = if (trackType == C.TRACK_TYPE_AUDIO) "Audio" else "Subtitle"
                    val label = format.label?.takeIf { it.isNotBlank() }
                        ?: format.language?.takeIf { it.isNotBlank() }?.uppercase()
                        ?: "$fallback ${result.size + if (includeOff) 0 else 1}"
                    result.add(mapOf(
                        "id" to "$rendererIndex:$groupIndex:$trackIndex",
                        "label" to label,
                        "language" to (format.language ?: ""),
                        "isSelected" to (currentGroup?.isTrackSelected(trackIndex) == true),
                        "isOff" to false
                    ))
                }
            }
        }
        return result
    }

    fun selectTrack(trackType: Int, id: String) {
        val mappedInfo = trackSelector.currentMappedTrackInfo ?: return
        if (id == "off" && trackType == C.TRACK_TYPE_TEXT) {
            var builder = trackSelector.buildUponParameters()
            for (rendererIndex in 0 until mappedInfo.rendererCount) {
                if (mappedInfo.getRendererType(rendererIndex) == trackType) {
                    builder = builder.clearSelectionOverrides(rendererIndex)
                        .setRendererDisabled(rendererIndex, true)
                }
            }
            trackSelector.setParameters(builder)
            return
        }
        val parts = id.split(":")
        val rendererIndex = parts.getOrNull(0)?.toIntOrNull() ?: return
        val groupIndex = parts.getOrNull(1)?.toIntOrNull() ?: return
        val trackIndex = parts.getOrNull(2)?.toIntOrNull() ?: return
        if (rendererIndex !in 0 until mappedInfo.rendererCount ||
            mappedInfo.getRendererType(rendererIndex) != trackType
        ) return
        val groups = mappedInfo.getTrackGroups(rendererIndex)
        if (groupIndex !in 0 until groups.length ||
            trackIndex !in 0 until groups[groupIndex].length
        ) return
        trackSelector.setParameters(
            trackSelector.buildUponParameters()
                .setRendererDisabled(rendererIndex, false)
                .clearSelectionOverrides(rendererIndex)
                .setSelectionOverride(
                    rendererIndex,
                    groups,
                    DefaultTrackSelector.SelectionOverride(groupIndex, trackIndex)
                )
        )
    }

    fun snapshot(): Map<String, Long> = mapOf(
        "positionMs" to player.currentPosition,
        "durationMs" to player.duration
    )

    fun diagnostics(): Map<String, Any> {
        val counters = player.videoDecoderCounters
        val renderedFrames = counters?.renderedOutputBufferCount?.toLong() ?: 0L
        val droppedFrames = counters?.droppedBufferCount?.toLong() ?: 0L
        val skippedFrames = counters?.skippedOutputBufferCount?.toLong() ?: 0L
        val format = player.videoFormat
        val refresh = (activity as? MainActivity)?.displayRefreshRateManager?.snapshot()
        val currentPosition = player.currentPosition
        val bufferedDuration = (player.bufferedPosition - currentPosition).coerceAtLeast(0L)
        val refreshStrategy = if ((refresh?.targetHz ?: 0f) > 0f) {
            "${refresh?.sourceFps} FPS -> ${refresh?.targetHz} Hz"
        } else {
            "Waiting for stable source FPS"
        }

        return mapOf(
            "engine" to "Native ExoPlayer2 SurfaceView",
            "media3Version" to "ExoPlayerLib 2.19.1 + FFmpeg audio",
            "androidApiLevel" to Build.VERSION.SDK_INT,
            "decoderName" to decoderName,
            "isHardwareDecoder" to isHardwareDecoder,
            "isDecoderVerified" to (decoderName != "Unknown"),
            "videoMime" to (format?.sampleMimeType ?: "N/A"),
            "videoCodecs" to (format?.codecs ?: "N/A"),
            "videoWidth" to (format?.width ?: 0),
            "videoHeight" to (format?.height ?: 0),
            "sourceFps" to sourceFps,
            "measuredFps" to sourceFps,
            "fpsConfidence" to if (sourceFps > 0f) "FORMAT" else "LOW",
            "requestedFrameRate" to (refresh?.sourceFps ?: 0f),
            "displayHzBefore" to 0f,
            "displayHz" to (refresh?.displayHz ?: 60f),
            "matchingMethod" to (refresh?.method ?: "WAITING"),
            "frameRateStrategy" to refreshStrategy,
            "frameRateMatchingStatus" to (refresh?.status ?: "WAITING"),
            "renderedFrames" to renderedFrames,
            "droppedFrames" to droppedFrames,
            "skippedFrames" to skippedFrames,
            "maxConsecutiveDropped" to (counters?.maxConsecutiveDroppedBufferCount ?: 0),
            "surfaceType" to "SurfaceView (direct native overlay)",
            "bufferDurationMs" to bufferedDuration,
            "rebufferCount" to rebufferCount,
            "startupTimeMs" to startupTimeMs,
            "positionMs" to currentPosition,
            "durationMs" to player.duration,
            "lastError" to lastPlaybackError,
            "avgProcessingOffsetMs" to pacingMedianMs,
            "frameProcessingSampleCount" to releaseDeltasNs.size,
            "pacingP95Ms" to pacingP95Ms
        )
    }

    fun dispose() {
        Exo2PlayerPlugin.instance?.setKeepScreenOn(false)
        player.clearVideoSurfaceView(surfaceView)
        player.release()
        (videoHost.parent as? FrameLayout)?.removeView(videoHost)
    }

    private fun sendEvent(type: String, data: Map<String, Any>) {
        val payload = HashMap(data)
        payload["event"] = type
        activity.runOnUiThread { Exo2PlayerPlugin.eventSink?.success(payload) }
    }
}
