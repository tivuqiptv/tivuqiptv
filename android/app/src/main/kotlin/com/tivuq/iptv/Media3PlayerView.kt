package com.tivuq.iptv

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DecoderCounters
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.video.VideoFrameMetadataListener
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlin.math.abs

@UnstableApi
class Media3PlayerView(
    private val context: Context,
    messenger: BinaryMessenger,
    id: Int
) : PlatformView {

    companion object {
        var activeInstance: Media3PlayerView? = null
        var eventSink: EventChannel.EventSink? = null
        var pendingUrl: String? = null
        var pendingUserAgent: String = "IPTVSmartersPlayer"
        var pendingHttpHeaders: Map<String, String> = emptyMap()
        var pendingTunneling: Boolean = false
        var pendingQuality: String = "auto"
        var isFrameRateMatchingEnabledGlobal: Boolean = true
    }

    private val playerView: PlayerView = PlayerView(context)
    private var exoPlayer: ExoPlayer? = null
    private var trackSelector: DefaultTrackSelector? = null

    // Video Metrics & Diagnostics state
    private var droppedFramesCount = 0L
    private var lastDecoderName: String = "Unknown"
    private var lastAudioDecoderName: String = "Unknown"
    private var isHardwareDecoder: Boolean = false
    private var isDecoderVerified: Boolean = false
    private var videoMime: String = "N/A"
    private var videoCodecs: String = "N/A"
    private var videoWidth = 0
    private var videoHeight = 0
    private var videoBitrate = 0
    private var videoTrackSupportStatus = "Unknown"
    private var audioMime: String = "N/A"
    private var selectedAudioLanguage: String = "N/A"
    private var selectedAudioChannels: Int = 0
    private var selectedAudioSampleRate: Int = 0
    private var sourceFps: Float = 0.0f
    private var rebufferCount = 0
    private var startupTimeMs = 0L
    private var playRequestedTimeMs = 0L
    private var enableTunneling = false
    private var isAsyncCodecQueueingEnabled = false
    private var lastPlaybackError: String = "None"

    // Frame Rate Matching State
    private var isFrameRateMatchingEnabled = isFrameRateMatchingEnabledGlobal
    private var requestedFrameRate = 0.0f
    private var displayHzBefore = 60.0f
    private var matchingMethod = "Adaptive display mode"
    private var frameRateStrategy = "Waiting for stable source FPS"
    private var frameRateMatchingStatus = if (isFrameRateMatchingEnabledGlobal) "WAITING" else "OFF"

    // Frame Pacing & Timestamps Metrics
    private var totalFrameProcessingOffsetUs = 0L
    private var frameProcessingSampleCount = 0
    private val presentationTimestampsUs = ArrayList<Long>()
    private var lastDisplayMatchedFps = 0f
    private var displayMatchCommitted = false

    // Audio Pipeline Diagnostics State
    private var audioSessionId = C.AUDIO_SESSION_ID_UNSET
    private var audioUnderrunCount = 0
    private var lastAudioSinkError: String = "None"
    private var lastAudioCodecError: String = "None"
    private var lastAudioPositionMs = 0L
    private var isAudioPositionAdvancing = false
    private var audioTrackSupportStatus = "Unknown"
    private var audioGroupsCount = 0

    init {
        activeInstance = this
        displayHzBefore = getDisplayRefreshRate()
        setupPlayerView()
        createPlayer()

        val urlToOpen = pendingUrl
        if (urlToOpen != null && urlToOpen.isNotEmpty()) {
            openUrlInternal(
                urlToOpen,
                pendingUserAgent,
                pendingTunneling,
                pendingQuality,
                pendingHttpHeaders
            )
            pendingUrl = null
        }
    }

    private fun setupPlayerView() {
        playerView.useController = false
        playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
    }

    private fun createPlayer() {
        val renderersFactory = DefaultRenderersFactory(context).apply {
            setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            setEnableDecoderFallback(true)
            // Eski Fire OS/MediaTek codec suruculeri zorlanmis asenkron
            // kuyruklamada surekli flush ederek goruntuyu dur-kalk oynatabiliyor.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                forceEnableMediaCodecAsynchronousQueueing()
                isAsyncCodecQueueingEnabled = true
            }
        }

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                15000,
                50000,
                1500,
                3000
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        trackSelector = DefaultTrackSelector(context)

        exoPlayer = ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(trackSelector!!)
            .setLoadControl(loadControl)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .build(),
                true
            )
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // TIVUQIPTV owns display-mode selection at screen level. Letting
            // ExoPlayer issue Surface frame-rate requests here caused a late
            // 50/60 Hz HDMI handshake after the live picture was already up.
            exoPlayer?.setVideoChangeFrameRateStrategy(0)
        }

        playerView.player = exoPlayer

        exoPlayer?.setVideoFrameMetadataListener(VideoFrameMetadataListener { presentationTimeUs, _, _, _ ->
            synchronized(presentationTimestampsUs) {
                presentationTimestampsUs.add(presentationTimeUs)
                if (presentationTimestampsUs.size > 150) {
                    presentationTimestampsUs.removeAt(0)
                }
                if (!displayMatchCommitted && presentationTimestampsUs.size >= 50) {
                    val deltas = presentationTimestampsUs.zipWithNext { first, second -> second - first }
                        .filter { it in 5_000L..100_000L }
                        .sorted()
                    if (deltas.size >= 25) {
                        val measuredFps = 1_000_000f / deltas[deltas.size / 2].toFloat()
                        val standards = floatArrayOf(23.976f, 24f, 25f, 29.97f, 30f, 50f, 59.94f, 60f)
                        val matchedFps = standards.minByOrNull { abs(it - measuredFps) } ?: measuredFps
                        if (abs(matchedFps - measuredFps) < 1f &&
                            abs(matchedFps - lastDisplayMatchedFps) > 0.5f
                        ) {
                            lastDisplayMatchedFps = matchedFps
                            displayMatchCommitted = true
                            Exo2PlayerPlugin.instance?.matchDisplayFrameRate(matchedFps)
                        }
                    }
                    if (presentationTimestampsUs.size >= 80) {
                        displayMatchCommitted = true
                    }
                }
            }
        })

        exoPlayer?.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                val isBuffering = state == Player.STATE_BUFFERING
                val isEnded = state == Player.STATE_ENDED

                if (state == Player.STATE_READY && playRequestedTimeMs > 0) {
                    startupTimeMs = System.currentTimeMillis() - playRequestedTimeMs
                    playRequestedTimeMs = 0
                }

                if (state == Player.STATE_READY && (exoPlayer?.playWhenReady == true)) {
                    Media3PlayerPlugin.instance?.setKeepScreenOn(true)
                }

                if (state == Player.STATE_BUFFERING) {
                    rebufferCount++
                }

                if (state == Player.STATE_ENDED) {
                    Media3PlayerPlugin.instance?.setKeepScreenOn(false)
                    resetFrameRateMatching()
                }

                sendEvent("onPlaybackState", mapOf(
                    "state" to state,
                    "isBuffering" to isBuffering,
                    "isEnded" to isEnded
                ))
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                sendEvent("onIsPlayingChanged", mapOf("isPlaying" to isPlaying))
                if (isPlaying) {
                    Media3PlayerPlugin.instance?.setKeepScreenOn(true)
                } else if (exoPlayer?.playbackState != Player.STATE_BUFFERING) {
                    Media3PlayerPlugin.instance?.setKeepScreenOn(false)
                    resetFrameRateMatching()
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                Media3PlayerPlugin.instance?.setKeepScreenOn(false)
                resetFrameRateMatching()
                lastPlaybackError = "[${error.errorCodeName}] ${error.message ?: "Playback Error"}"
                sendEvent("onError", mapOf(
                    "errorCode" to error.errorCodeName,
                    "errorMessage" to (error.message ?: "Playback Error")
                ))
            }

            override fun onTracksChanged(tracks: Tracks) {
                parseTracks(tracks)
            }
        })

        exoPlayer?.addAnalyticsListener(object : AnalyticsListener {
            override fun onDroppedVideoFrames(
                eventTime: AnalyticsListener.EventTime,
                droppedFrames: Int,
                elapsedMs: Long
            ) {
                droppedFramesCount += droppedFrames
            }

            override fun onVideoFrameProcessingOffset(
                eventTime: AnalyticsListener.EventTime,
                totalProcessingOffsetUs: Long,
                frameCount: Int
            ) {
                this@Media3PlayerView.totalFrameProcessingOffsetUs += totalProcessingOffsetUs
                this@Media3PlayerView.frameProcessingSampleCount += frameCount
            }

            override fun onVideoDecoderInitialized(
                eventTime: AnalyticsListener.EventTime,
                decoderName: String,
                initializedTimestampMs: Long,
                initializationDurationMs: Long
            ) {
                lastDecoderName = decoderName
                isDecoderVerified = true
                val lower = decoderName.lowercase()
                isHardwareDecoder = !lower.contains("omx.google") &&
                                    !lower.contains("c2.android") &&
                                    !lower.contains(".sw.") &&
                                    !lower.startsWith("omx.ffmpeg")
            }

            override fun onAudioDecoderInitialized(
                eventTime: AnalyticsListener.EventTime,
                decoderName: String,
                initializedTimestampMs: Long,
                initializationDurationMs: Long
            ) {
                lastAudioDecoderName = decoderName
            }

            override fun onAudioUnderrun(
                eventTime: AnalyticsListener.EventTime,
                bufferSize: Int,
                bufferSizeMs: Long,
                elapsedSinceLastFeedMs: Long
            ) {
                audioUnderrunCount++
            }

            override fun onAudioSinkError(
                eventTime: AnalyticsListener.EventTime,
                audioSinkError: Exception
            ) {
                lastAudioSinkError = audioSinkError.message ?: "AudioSink Error"
            }

            override fun onAudioCodecError(
                eventTime: AnalyticsListener.EventTime,
                audioCodecError: Exception
            ) {
                lastAudioCodecError = audioCodecError.message ?: "AudioCodec Error"
            }

            override fun onVideoInputFormatChanged(
                eventTime: AnalyticsListener.EventTime,
                format: Format,
                decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?
            ) {
                videoMime = format.sampleMimeType ?: "N/A"
                videoCodecs = format.codecs ?: "N/A"
                videoWidth = format.width
                videoHeight = format.height
                videoBitrate = format.bitrate
                if (format.frameRate > 0) {
                    sourceFps = format.frameRate
                    displayMatchCommitted = true
                    Exo2PlayerPlugin.instance?.matchDisplayFrameRate(
                        format.frameRate,
                        exactFormat = true
                    )
                }
            }

            override fun onAudioInputFormatChanged(
                eventTime: AnalyticsListener.EventTime,
                format: Format,
                decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?
            ) {
                audioMime = format.sampleMimeType ?: "N/A"
                selectedAudioLanguage = format.language ?: "N/A"
                selectedAudioChannels = format.channelCount
                selectedAudioSampleRate = format.sampleRate
            }
        })

        applyTunneling(enableTunneling)
    }

    private fun applyTunneling(enabled: Boolean) {
        // Tunneling can be unstable with vendor codecs on older Android APIs.
        val safeEnabled = enabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
        enableTunneling = safeEnabled
        trackSelector?.parameters = trackSelector?.buildUponParameters()
            ?.setTunnelingEnabled(safeEnabled)
            ?.build() ?: return
    }

    private fun parseTracks(tracks: Tracks) {
        var audioSelected = false
        var hasAudioGroup = false
        var firstSupportedAudioGroup: Tracks.Group? = null
        audioGroupsCount = 0

        val audioTracksList = mutableListOf<Map<String, Any>>()
        for (group in tracks.groups) {
            if (group.type == C.TRACK_TYPE_AUDIO) {
                hasAudioGroup = true
                audioGroupsCount++

                val supportLevel = if (group.length > 0) group.getTrackSupport(0) else C.FORMAT_HANDLED
                audioTrackSupportStatus = when (supportLevel) {
                    C.FORMAT_HANDLED -> "FORMAT_HANDLED"
                    C.FORMAT_EXCEEDS_CAPABILITIES -> "EXCEEDS_CAPABILITIES"
                    C.FORMAT_UNSUPPORTED_DRM -> "UNSUPPORTED_DRM"
                    C.FORMAT_UNSUPPORTED_SUBTYPE -> "UNSUPPORTED_SUBTYPE"
                    C.FORMAT_UNSUPPORTED_TYPE -> "UNSUPPORTED_TYPE"
                    else -> "SUPPORT_UNKNOWN($supportLevel)"
                }

                if (group.isSupported && firstSupportedAudioGroup == null) {
                    firstSupportedAudioGroup = group
                }

                for (i in 0 until group.length) {
                    val format = group.getTrackFormat(i)
                    val isSelected = group.isTrackSelected(i)
                    if (isSelected) {
                        audioSelected = true
                        audioMime = format.sampleMimeType ?: audioMime
                        selectedAudioLanguage = format.language ?: selectedAudioLanguage
                        selectedAudioChannels = if (format.channelCount > 0) format.channelCount else selectedAudioChannels
                        selectedAudioSampleRate = if (format.sampleRate > 0) format.sampleRate else selectedAudioSampleRate
                    }
                    audioTracksList.add(mapOf(
                        "index" to i,
                        "mime" to (format.sampleMimeType ?: "N/A"),
                        "language" to (format.language ?: "N/A"),
                        "channels" to format.channelCount,
                        "sampleRate" to format.sampleRate,
                        "support" to audioTrackSupportStatus,
                        "isSelected" to isSelected
                    ))
                }
            } else if (group.type == C.TRACK_TYPE_VIDEO) {
                val supportLevel = if (group.length > 0) group.getTrackSupport(0) else C.FORMAT_HANDLED
                videoTrackSupportStatus = when (supportLevel) {
                    C.FORMAT_HANDLED -> "FORMAT_HANDLED"
                    C.FORMAT_EXCEEDS_CAPABILITIES -> "EXCEEDS_CAPABILITIES"
                    C.FORMAT_UNSUPPORTED_DRM -> "UNSUPPORTED_DRM"
                    C.FORMAT_UNSUPPORTED_SUBTYPE -> "UNSUPPORTED_SUBTYPE"
                    C.FORMAT_UNSUPPORTED_TYPE -> "UNSUPPORTED_TYPE"
                    else -> "SUPPORT_UNKNOWN($supportLevel)"
                }

                for (i in 0 until group.length) {
                    if (group.isTrackSelected(i)) {
                        val format = group.getTrackFormat(i)
                        videoMime = format.sampleMimeType ?: videoMime
                        videoCodecs = format.codecs ?: videoCodecs
                        videoWidth = if (format.width > 0) format.width else videoWidth
                        videoHeight = if (format.height > 0) format.height else videoHeight
                        videoBitrate = if (format.bitrate > 0) format.bitrate else videoBitrate
                        if (format.frameRate > 0) {
                            sourceFps = format.frameRate
                        }
                    }
                }
            }
        }

        if (hasAudioGroup && !audioSelected && firstSupportedAudioGroup != null) {
            val override = TrackSelectionOverride(firstSupportedAudioGroup.mediaTrackGroup, 0)
            trackSelector?.setParameters(
                trackSelector?.buildUponParameters()
                    ?.clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                    ?.addOverride(override)
                    ?.build() ?: return
            )
        }

        sendEvent("onAudioTracksChanged", mapOf("tracks" to audioTracksList))
    }

    fun openUrlInternal(
        url: String,
        userAgent: String,
        tunneling: Boolean,
        quality: String,
        httpHeaders: Map<String, String>
    ) {
        if (url.isEmpty()) return
        playRequestedTimeMs = System.currentTimeMillis()
        droppedFramesCount = 0
        rebufferCount = 0
        totalFrameProcessingOffsetUs = 0L
        frameProcessingSampleCount = 0
        audioUnderrunCount = 0
        lastAudioSinkError = "None"
        lastAudioCodecError = "None"
        lastPlaybackError = "None"

        resetFrameRateMatching()

        synchronized(presentationTimestampsUs) {
            presentationTimestampsUs.clear()
            lastDisplayMatchedFps = 0f
            displayMatchCommitted = false
        }

        Media3PlayerPlugin.instance?.setKeepScreenOn(true)

        trackSelector?.setParameters(
            trackSelector?.buildUponParameters()
                ?.clearOverrides()
                ?.setTunnelingEnabled(
                    tunneling && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                )
                ?.build() ?: return
        )

        applyTunneling(tunneling)
        applyQuality(quality)

        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(15000)
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(httpHeaders)

        val mediaItem = MediaItem.fromUri(url)
        val mediaSource = if (url.lowercase().contains(".m3u8") || url.lowercase().contains("type=m3u8")) {
            HlsMediaSource.Factory(dataSourceFactory).createMediaSource(mediaItem)
        } else {
            ProgressiveMediaSource.Factory(dataSourceFactory).createMediaSource(mediaItem)
        }

        exoPlayer?.setMediaSource(mediaSource)
        exoPlayer?.prepare()
        exoPlayer?.playWhenReady = true
        exoPlayer?.volume = 1.0f
    }

    fun pauseForBackground() {
        exoPlayer?.pause()
        Media3PlayerPlugin.instance?.setKeepScreenOn(false)
        resetFrameRateMatching()
    }

    private fun applyQuality(quality: String) {
        val (maxWidth, maxHeight) = when (quality.lowercase()) {
            "720p" -> 1280 to 720
            "1080p" -> 1920 to 1080
            "4k" -> 3840 to 2160
            else -> Int.MAX_VALUE to Int.MAX_VALUE
        }
        trackSelector?.parameters = trackSelector?.buildUponParameters()
            ?.setMaxVideoSize(maxWidth, maxHeight)
            ?.build() ?: return
    }

    private fun applyFrameRateMatching(fps: Double) {
        if (!isFrameRateMatchingEnabled) {
            frameRateMatchingStatus = "OFF"
            matchingMethod = "OFF"
            return
        }

        if (fps <= 0.0) {
            frameRateMatchingStatus = "WAITING"
            return
        }

        val targetFps = fps.toFloat()

        if (requestedFrameRate == targetFps && frameRateMatchingStatus == "ACTIVE") {
            return
        }

        requestedFrameRate = targetFps

        val surfaceView = playerView.videoSurfaceView as? SurfaceView
        val surface = surfaceView?.holder?.surface
        val activity = Media3PlayerPlugin.instance?.activity as? MainActivity
        activity?.displayRefreshRateManager?.requestContentFrameRate(targetFps, surface)
        matchingMethod = "Adaptive display mode"
        frameRateMatchingStatus = "WAITING"
        frameRateStrategy = "Source $targetFps FPS"
    }

    private fun resetFrameRateMatching() {
        if (requestedFrameRate > 0f && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val surfaceView = playerView.videoSurfaceView as? SurfaceView
                val surface = surfaceView?.holder?.surface
                if (surface != null && surface.isValid) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        surface.setFrameRate(
                            0.0f,
                            Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                            Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        surface.setFrameRate(
                            0.0f,
                            Surface.FRAME_RATE_COMPATIBILITY_DEFAULT
                        )
                    }
                }
            } catch (_: Exception) {}
        }
        requestedFrameRate = 0.0f
        frameRateMatchingStatus = if (isFrameRateMatchingEnabled) "WAITING" else "OFF"
    }

    private fun computeMeasuredFps(): Triple<Double, String, Int> {
        val timestamps: List<Long>
        synchronized(presentationTimestampsUs) {
            timestamps = ArrayList(presentationTimestampsUs)
        }

        if (timestamps.size < 10) {
            return Triple(0.0, "LOW", timestamps.size)
        }

        val deltasUs = mutableListOf<Long>()
        for (i in 1 until timestamps.size) {
            val delta = timestamps[i] - timestamps[i - 1]
            if (delta in 5000..200000) {
                deltasUs.add(delta)
            }
        }

        if (deltasUs.size < 8) {
            return Triple(0.0, "LOW", deltasUs.size)
        }

        deltasUs.sort()
        val medianDeltaUs = deltasUs[deltasUs.size / 2].toDouble()
        if (medianDeltaUs <= 0) return Triple(0.0, "LOW", deltasUs.size)

        val rawFps = 1_000_000.0 / medianDeltaUs

        val standardRates = doubleArrayOf(23.976, 24.0, 25.0, 29.97, 30.0, 50.0, 59.94, 60.0)
        var quantizedFps = rawFps
        for (rate in standardRates) {
            if (abs(rawFps - rate) <= 0.8) {
                quantizedFps = rate
                break
            }
        }

        val confidence = when {
            deltasUs.size >= 50 -> "HIGH"
            deltasUs.size >= 20 -> "MEDIUM"
            else -> "LOW"
        }

        return Triple(quantizedFps, confidence, deltasUs.size)
    }

    override fun getView(): View {
        return playerView
    }

    private fun trackOptions(trackType: Int, includeOff: Boolean): List<Map<String, Any>> {
        val groups = exoPlayer?.currentTracks?.groups ?: emptyList()
        val result = mutableListOf<Map<String, Any>>()
        if (includeOff) {
            val disabled = trackSelector?.parameters?.disabledTrackTypes?.contains(trackType) == true ||
                groups.none { it.type == trackType && it.isSelected }
            result.add(mapOf(
                "id" to "off",
                "label" to "Off",
                "language" to "",
                "isSelected" to disabled,
                "isOff" to true
            ))
        }
        groups.forEachIndexed { groupIndex, group ->
            if (group.type != trackType) return@forEachIndexed
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSupported(trackIndex)) continue
                val format = group.getTrackFormat(trackIndex)
                val fallback = if (trackType == C.TRACK_TYPE_AUDIO) "Audio" else "Subtitle"
                val label = format.label?.takeIf { it.isNotBlank() }
                    ?: format.language?.takeIf { it.isNotBlank() }?.uppercase()
                    ?: "$fallback ${result.size + if (includeOff) 0 else 1}"
                result.add(mapOf(
                    "id" to "$groupIndex:$trackIndex",
                    "label" to label,
                    "language" to (format.language ?: ""),
                    "isSelected" to group.isTrackSelected(trackIndex),
                    "isOff" to false
                ))
            }
        }
        return result
    }

    private fun selectTrack(trackType: Int, id: String) {
        val selector = trackSelector ?: return
        if (id == "off" && trackType == C.TRACK_TYPE_TEXT) {
            selector.parameters = selector.buildUponParameters()
                .clearOverridesOfType(trackType)
                .setTrackTypeDisabled(trackType, true)
                .build()
            return
        }
        val parts = id.split(":")
        val groupIndex = parts.getOrNull(0)?.toIntOrNull() ?: return
        val trackIndex = parts.getOrNull(1)?.toIntOrNull() ?: return
        val group = exoPlayer?.currentTracks?.groups?.getOrNull(groupIndex) ?: return
        if (group.type != trackType || trackIndex !in 0 until group.length) return
        val override = TrackSelectionOverride(group.mediaTrackGroup, trackIndex)
        selector.parameters = selector.buildUponParameters()
            .clearOverridesOfType(trackType)
            .setTrackTypeDisabled(trackType, false)
            .addOverride(override)
            .build()
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openUrl" -> {
                val url = call.argument<String>("url") ?: ""
                val userAgent = call.argument<String>("userAgent") ?: "IPTVSmartersPlayer"
                val tunneling = call.argument<Boolean>("enableTunneling") ?: false
                val quality = call.argument<String>("quality") ?: "auto"
                val httpHeaders = call.argument<Map<String, String>>("httpHeaders").orEmpty()
                openUrlInternal(
                    url,
                    httpHeaders["User-Agent"] ?: userAgent,
                    tunneling,
                    quality,
                    httpHeaders
                )
                result.success(true)
            }
            "play" -> {
                exoPlayer?.play()
                Media3PlayerPlugin.instance?.setKeepScreenOn(true)
                result.success(null)
            }
            "pause" -> {
                exoPlayer?.pause()
                Media3PlayerPlugin.instance?.setKeepScreenOn(false)
                resetFrameRateMatching()
                result.success(null)
            }
            "stop" -> {
                exoPlayer?.stop()
                Media3PlayerPlugin.instance?.setKeepScreenOn(false)
                resetFrameRateMatching()
                result.success(null)
            }
            "seek" -> {
                val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                exoPlayer?.seekTo(positionMs)
                result.success(null)
            }
            "setVolume" -> {
                val volume = call.argument<Number>("volume")?.toFloat() ?: 1.0f
                exoPlayer?.volume = volume
                result.success(null)
            }
            "setTunneling" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                applyTunneling(enabled)
                result.success(null)
            }
            "getAudioTracks" -> result.success(trackOptions(C.TRACK_TYPE_AUDIO, false))
            "getSubtitleTracks" -> result.success(trackOptions(C.TRACK_TYPE_TEXT, true))
            "selectAudioTrack" -> {
                selectTrack(C.TRACK_TYPE_AUDIO, call.argument<String>("id") ?: "")
                result.success(true)
            }
            "selectSubtitleTrack" -> {
                selectTrack(C.TRACK_TYPE_TEXT, call.argument<String>("id") ?: "off")
                result.success(true)
            }
            "setFrameRateMatchingEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                isFrameRateMatchingEnabled = enabled
                isFrameRateMatchingEnabledGlobal = enabled
                if (!enabled) {
                    resetFrameRateMatching()
                }
                result.success(true)
            }
            "getDiagnostics" -> {
                val currentPosition = exoPlayer?.currentPosition ?: 0L
                val duration = exoPlayer?.duration ?: 0L
                val bufferedPosition = exoPlayer?.bufferedPosition ?: 0L
                val bufferDuration = (bufferedPosition - currentPosition).coerceAtLeast(0L)

                val videoCounters = exoPlayer?.videoDecoderCounters
                val renderedOutputBufferCount = videoCounters?.renderedOutputBufferCount?.toLong() ?: 0L
                val decoderDroppedCount = videoCounters?.droppedBufferCount?.toLong() ?: droppedFramesCount
                val skippedBufferCount = videoCounters?.skippedOutputBufferCount?.toLong() ?: 0L
                val maxConsecutiveDroppedCount = videoCounters?.maxConsecutiveDroppedBufferCount ?: 0

                val selectedAudioGroup = exoPlayer?.currentTracks?.groups?.firstOrNull { it.type == C.TRACK_TYPE_AUDIO && it.isSelected }
                val isAudioRendererEnabled = selectedAudioGroup != null
                val rendererStatusString = if (isAudioRendererEnabled) "Renderer ACTIVE (Track Selected)" else "Renderer DISABLED (No Track Selected)"

                if (currentPosition > lastAudioPositionMs) {
                    isAudioPositionAdvancing = true
                }
                lastAudioPositionMs = currentPosition

                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                val sysVolume = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: -1
                val maxSysVolume = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: -1

                val avgProcessingOffsetMs = if (frameProcessingSampleCount > 0) {
                    (totalFrameProcessingOffsetUs.toDouble() / frameProcessingSampleCount.toDouble()) / 1000.0
                } else {
                    0.0
                }

                val (measuredFps, fpsConfidence, fpsSampleCount) = computeMeasuredFps()

                // Metadata-less live streams use measured presentation timestamps.
                if (isFrameRateMatchingEnabled && (fpsConfidence == "HIGH" || fpsConfidence == "MEDIUM") && measuredFps > 0.0) {
                    applyFrameRateMatching(measuredFps)
                }

                val refreshSnapshot = (Media3PlayerPlugin.instance?.activity as? MainActivity)
                    ?.displayRefreshRateManager?.snapshot()
                if (refreshSnapshot != null) {
                    matchingMethod = refreshSnapshot.method
                    frameRateMatchingStatus = refreshSnapshot.status
                    frameRateStrategy = if (refreshSnapshot.targetHz > 0f) {
                        "${refreshSnapshot.sourceFps} FPS -> ${refreshSnapshot.targetHz} Hz"
                    } else {
                        "Waiting for stable source FPS"
                    }
                }

                var resolvedFps = sourceFps
                if (resolvedFps <= 0f) {
                    val vf = exoPlayer?.videoFormat
                    if (vf != null && vf.frameRate > 0f) {
                        resolvedFps = vf.frameRate
                    }
                }

                val decoderStatusString = if (!isDecoderVerified) {
                    "Unknown"
                } else if (isHardwareDecoder) {
                    "HW ($lastDecoderName)"
                } else {
                    "SW ($lastDecoderName)"
                }

                val surfaceTypeString = playerView.videoSurfaceView?.javaClass?.simpleName ?: "SurfaceView (PlatformView)"

                val metrics = mapOf(
                    "engine" to "Native Media3 (ExoPlayer)",
                    "media3Version" to "1.11.0",
                    "androidApiLevel" to Build.VERSION.SDK_INT,
                    "decoderName" to lastDecoderName,
                    "audioDecoderName" to lastAudioDecoderName,
                    "isHardwareDecoder" to isHardwareDecoder,
                    "isDecoderVerified" to isDecoderVerified,
                    "decoderStatusString" to decoderStatusString,
                    "videoMime" to videoMime,
                    "videoCodecs" to videoCodecs,
                    "videoWidth" to (if (videoWidth > 0) videoWidth else (exoPlayer?.videoSize?.width ?: 0)),
                    "videoHeight" to (if (videoHeight > 0) videoHeight else (exoPlayer?.videoSize?.height ?: 0)),
                    "videoBitrate" to videoBitrate,
                    "videoTrackSupport" to videoTrackSupportStatus,
                    "audioMime" to audioMime,
                    "sourceFps" to resolvedFps,
                    "measuredFps" to measuredFps,
                    "fpsConfidence" to fpsConfidence,
                    "fpsSampleCount" to fpsSampleCount,
                    "requestedFrameRate" to requestedFrameRate,
                    "displayHzBefore" to displayHzBefore,
                    "displayHz" to (refreshSnapshot?.displayHz ?: getDisplayRefreshRate()),
                    "matchingMethod" to matchingMethod,
                    "frameRateStrategy" to frameRateStrategy,
                    "frameRateMatchingStatus" to frameRateMatchingStatus,
                    "renderedFrames" to renderedOutputBufferCount,
                    "droppedFrames" to decoderDroppedCount,
                    "skippedFrames" to skippedBufferCount,
                    "maxConsecutiveDropped" to maxConsecutiveDroppedCount,
                    "surfaceType" to surfaceTypeString,
                    "bufferDurationMs" to bufferDuration,
                    "rebufferCount" to rebufferCount,
                    "startupTimeMs" to startupTimeMs,
                    "tunnelingStatus" to enableTunneling,
                    "asyncCodecQueueing" to isAsyncCodecQueueingEnabled,
                    "keepScreenOnStatus" to Media3PlayerPlugin.isKeepScreenOnActive,
                    "selectedAudioLanguage" to selectedAudioLanguage,
                    "selectedAudioChannels" to selectedAudioChannels,
                    "selectedAudioSampleRate" to selectedAudioSampleRate,
                    "audioGroupsCount" to audioGroupsCount,
                    "positionMs" to currentPosition,
                    "durationMs" to duration,
                    "lastError" to lastPlaybackError,

                    "avgProcessingOffsetMs" to avgProcessingOffsetMs,
                    "frameProcessingSampleCount" to frameProcessingSampleCount,

                    "playerVolume" to (exoPlayer?.volume ?: 1.0f),
                    "deviceVolume" to sysVolume,
                    "maxDeviceVolume" to maxSysVolume,
                    "audioSessionId" to (exoPlayer?.audioSessionId ?: C.AUDIO_SESSION_ID_UNSET),
                    "isAudioRendererEnabled" to isAudioRendererEnabled,
                    "rendererStatusString" to rendererStatusString,
                    "audioTrackSupportStatus" to audioTrackSupportStatus,
                    "isAudioPositionAdvancing" to isAudioPositionAdvancing,
                    "audioUnderrunCount" to audioUnderrunCount,
                    "lastAudioSinkError" to lastAudioSinkError,
                    "lastAudioCodecError" to lastAudioCodecError
                )
                result.success(metrics)
            }
            "getPlaybackSnapshot" -> {
                result.success(mapOf(
                    "positionMs" to (exoPlayer?.currentPosition ?: 0L),
                    "durationMs" to (exoPlayer?.duration ?: 0L)
                ))
            }
            "dispose" -> {
                dispose()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun getDisplayRefreshRate(): Float {
        return try {
            val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                context.display?.mode?.refreshRate ?: 60.0f
            } else {
                @Suppress("DEPRECATION")
                wm.defaultDisplay?.refreshRate ?: 60.0f
            }
        } catch (e: Exception) {
            60.0f
        }
    }

    private fun sendEvent(eventType: String, data: Map<String, Any>) {
        val payload = HashMap<String, Any>(data)
        payload["event"] = eventType
        val sink = eventSink ?: return
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            sink.success(payload)
        }
    }

    override fun dispose() {
        if (activeInstance == this) {
            activeInstance = null
        }
        Media3PlayerPlugin.instance?.setKeepScreenOn(false)
        resetFrameRateMatching()
        exoPlayer?.release()
        exoPlayer = null
        (playerView.parent as? FrameLayout)?.removeView(playerView)
    }
}
