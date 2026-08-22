class PlaybackDiagnostics {
  final String engine;
  final String media3Version;
  final int androidApiLevel;
  final String decoderName;
  final String audioDecoderName;
  final bool isHardwareDecoder;
  final bool isDecoderVerified;
  final String videoMime;
  final String videoCodecs;
  final int videoWidth;
  final int videoHeight;
  final int videoBitrate;
  final String videoTrackSupport;
  final String audioMime;
  final double sourceFps;
  final double measuredFps;
  final String fpsConfidence;
  final int fpsSampleCount;
  final double requestedFrameRate;
  final double displayHzBefore;
  final double displayHz;
  final String matchingMethod;
  final String frameRateStrategy;
  final String frameRateMatchingStatus;
  final int renderedFrames;
  final int droppedFrames;
  final int skippedFrames;
  final int maxConsecutiveDropped;
  final String surfaceType;
  final int bufferDurationMs;
  final int rebufferCount;
  final int startupTimeMs;
  final bool tunnelingStatus;
  final bool asyncCodecQueueing;
  final bool keepScreenOnStatus;
  final String selectedAudioLanguage;
  final int selectedAudioChannels;
  final int selectedAudioSampleRate;
  final int audioGroupsCount;
  final int positionMs;
  final int durationMs;
  final String lastError;

  // Frame Pacing
  final double avgProcessingOffsetMs;
  final int frameProcessingSampleCount;
  final double pacingP95Ms;

  // Audio Pipeline Diagnostics
  final double playerVolume;
  final int deviceVolume;
  final int maxDeviceVolume;
  final int audioSessionId;
  final bool isAudioRendererEnabled;
  final String rendererStatusString;
  final String audioTrackSupportStatus;
  final bool isAudioPositionAdvancing;
  final int audioUnderrunCount;
  final String lastAudioSinkError;
  final String lastAudioCodecError;

  const PlaybackDiagnostics({
    this.engine = 'Unknown',
    this.media3Version = 'N/A',
    this.androidApiLevel = 0,
    this.decoderName = 'Unknown',
    this.audioDecoderName = 'Unknown',
    this.isHardwareDecoder = false,
    this.isDecoderVerified = false,
    this.videoMime = 'N/A',
    this.videoCodecs = 'N/A',
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.videoBitrate = 0,
    this.videoTrackSupport = 'Unknown',
    this.audioMime = 'N/A',
    this.sourceFps = 0.0,
    this.measuredFps = 0.0,
    this.fpsConfidence = 'LOW',
    this.fpsSampleCount = 0,
    this.requestedFrameRate = 0.0,
    this.displayHzBefore = 60.0,
    this.displayHz = 60.0,
    this.matchingMethod = 'unsupported',
    this.frameRateStrategy = 'Unsupported (Requires Android 11+)',
    this.frameRateMatchingStatus = 'UNSUPPORTED (API < 30)',
    this.renderedFrames = 0,
    this.droppedFrames = 0,
    this.skippedFrames = 0,
    this.maxConsecutiveDropped = 0,
    this.surfaceType = 'SurfaceView (PlatformView)',
    this.bufferDurationMs = 0,
    this.rebufferCount = 0,
    this.startupTimeMs = 0,
    this.tunnelingStatus = false,
    this.asyncCodecQueueing = false,
    this.keepScreenOnStatus = false,
    this.selectedAudioLanguage = 'N/A',
    this.selectedAudioChannels = 0,
    this.selectedAudioSampleRate = 0,
    this.audioGroupsCount = 0,
    this.positionMs = 0,
    this.durationMs = 0,
    this.lastError = 'None',
    this.avgProcessingOffsetMs = 0.0,
    this.frameProcessingSampleCount = 0,
    this.pacingP95Ms = 0.0,
    this.playerVolume = 1.0,
    this.deviceVolume = -1,
    this.maxDeviceVolume = -1,
    this.audioSessionId = -1,
    this.isAudioRendererEnabled = false,
    this.rendererStatusString = 'Unknown',
    this.audioTrackSupportStatus = 'Unknown',
    this.isAudioPositionAdvancing = false,
    this.audioUnderrunCount = 0,
    this.lastAudioSinkError = 'None',
    this.lastAudioCodecError = 'None',
  });

  factory PlaybackDiagnostics.fromMap(Map<dynamic, dynamic> map) {
    return PlaybackDiagnostics(
      engine: map['engine']?.toString() ?? 'Native Media3',
      media3Version: map['media3Version']?.toString() ?? '1.11.0',
      androidApiLevel: (map['androidApiLevel'] as num?)?.toInt() ?? 0,
      decoderName: map['decoderName']?.toString() ?? 'Unknown',
      audioDecoderName: map['audioDecoderName']?.toString() ?? 'Unknown',
      isHardwareDecoder: map['isHardwareDecoder'] as bool? ?? false,
      isDecoderVerified: map['isDecoderVerified'] as bool? ?? false,
      videoMime: map['videoMime']?.toString() ?? 'N/A',
      videoCodecs: map['videoCodecs']?.toString() ?? 'N/A',
      videoWidth: (map['videoWidth'] as num?)?.toInt() ?? 0,
      videoHeight: (map['videoHeight'] as num?)?.toInt() ?? 0,
      videoBitrate: (map['videoBitrate'] as num?)?.toInt() ?? 0,
      videoTrackSupport: map['videoTrackSupport']?.toString() ?? 'Unknown',
      audioMime: map['audioMime']?.toString() ?? 'N/A',
      sourceFps: (map['sourceFps'] as num?)?.toDouble() ?? 0.0,
      measuredFps: (map['measuredFps'] as num?)?.toDouble() ?? 0.0,
      fpsConfidence: map['fpsConfidence']?.toString() ?? 'LOW',
      fpsSampleCount: (map['fpsSampleCount'] as num?)?.toInt() ?? 0,
      requestedFrameRate:
          (map['requestedFrameRate'] as num?)?.toDouble() ?? 0.0,
      displayHzBefore: (map['displayHzBefore'] as num?)?.toDouble() ?? 60.0,
      displayHz: (map['displayHz'] as num?)?.toDouble() ?? 60.0,
      matchingMethod: map['matchingMethod']?.toString() ?? 'unsupported',
      frameRateStrategy: map['frameRateStrategy']?.toString() ??
          'Unsupported (Requires Android 11+)',
      frameRateMatchingStatus: map['frameRateMatchingStatus']?.toString() ??
          'UNSUPPORTED (API < 30)',
      renderedFrames: (map['renderedFrames'] as num?)?.toInt() ?? 0,
      droppedFrames: (map['droppedFrames'] as num?)?.toInt() ?? 0,
      skippedFrames: (map['skippedFrames'] as num?)?.toInt() ?? 0,
      maxConsecutiveDropped:
          (map['maxConsecutiveDropped'] as num?)?.toInt() ?? 0,
      surfaceType:
          map['surfaceType']?.toString() ?? 'SurfaceView (PlatformView)',
      bufferDurationMs: (map['bufferDurationMs'] as num?)?.toInt() ?? 0,
      rebufferCount: (map['rebufferCount'] as num?)?.toInt() ?? 0,
      startupTimeMs: (map['startupTimeMs'] as num?)?.toInt() ?? 0,
      tunnelingStatus: map['tunnelingStatus'] as bool? ?? false,
      asyncCodecQueueing: map['asyncCodecQueueing'] as bool? ?? false,
      keepScreenOnStatus: map['keepScreenOnStatus'] as bool? ?? false,
      selectedAudioLanguage: map['selectedAudioLanguage']?.toString() ?? 'N/A',
      selectedAudioChannels:
          (map['selectedAudioChannels'] as num?)?.toInt() ?? 0,
      selectedAudioSampleRate:
          (map['selectedAudioSampleRate'] as num?)?.toInt() ?? 0,
      audioGroupsCount: (map['audioGroupsCount'] as num?)?.toInt() ?? 0,
      positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      lastError: map['lastError']?.toString() ?? 'None',
      avgProcessingOffsetMs:
          (map['avgProcessingOffsetMs'] as num?)?.toDouble() ?? 0.0,
      frameProcessingSampleCount:
          (map['frameProcessingSampleCount'] as num?)?.toInt() ?? 0,
      pacingP95Ms: (map['pacingP95Ms'] as num?)?.toDouble() ?? 0.0,
      playerVolume: (map['playerVolume'] as num?)?.toDouble() ?? 1.0,
      deviceVolume: (map['deviceVolume'] as num?)?.toInt() ?? -1,
      maxDeviceVolume: (map['maxDeviceVolume'] as num?)?.toInt() ?? -1,
      audioSessionId: (map['audioSessionId'] as num?)?.toInt() ?? -1,
      isAudioRendererEnabled: map['isAudioRendererEnabled'] as bool? ?? false,
      rendererStatusString:
          map['rendererStatusString']?.toString() ?? 'Unknown',
      audioTrackSupportStatus:
          map['audioTrackSupportStatus']?.toString() ?? 'Unknown',
      isAudioPositionAdvancing:
          map['isAudioPositionAdvancing'] as bool? ?? false,
      audioUnderrunCount: (map['audioUnderrunCount'] as num?)?.toInt() ?? 0,
      lastAudioSinkError: map['lastAudioSinkError']?.toString() ?? 'None',
      lastAudioCodecError: map['lastAudioCodecError']?.toString() ?? 'None',
    );
  }

  double get droppedFramePercentage {
    final total = renderedFrames + droppedFrames;
    if (total <= 0) return 0.0;
    return (droppedFrames / total) * 100.0;
  }
}
