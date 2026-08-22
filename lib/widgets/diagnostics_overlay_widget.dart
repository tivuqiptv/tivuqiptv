import 'package:flutter/material.dart';
import '../player/playback_diagnostics.dart';

class DiagnosticsOverlayWidget extends StatelessWidget {
  final PlaybackDiagnostics diagnostics;
  final bool visible;

  const DiagnosticsOverlayWidget({
    super.key,
    required this.diagnostics,
    this.visible = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final badgeText = !diagnostics.isDecoderVerified
        ? 'DECODER UNKNOWN'
        : (diagnostics.isHardwareDecoder ? 'HW DECODER' : 'SW DECODER');

    final badgeColor = !diagnostics.isDecoderVerified
        ? Colors.grey.shade700
        : (diagnostics.isHardwareDecoder
            ? Colors.green.shade800
            : Colors.orange.shade800);

    final totalFrames = diagnostics.renderedFrames + diagnostics.droppedFrames;
    final framesDisplay = totalFrames > 0
        ? 'Rendered: ${diagnostics.renderedFrames} | Dropped: ${diagnostics.droppedFrames} (${diagnostics.droppedFramePercentage.toStringAsFixed(1)}%)'
        : 'Rendered: ${diagnostics.renderedFrames} | Dropped: ${diagnostics.droppedFrames}';

    final pacingDisplay = diagnostics.pacingP95Ms > 0
        ? '${diagnostics.avgProcessingOffsetMs.toStringAsFixed(2)} ms median / ${diagnostics.pacingP95Ms.toStringAsFixed(2)} ms p95'
        : diagnostics.frameProcessingSampleCount > 0
            ? '${diagnostics.avgProcessingOffsetMs.toStringAsFixed(2)} ms (${diagnostics.frameProcessingSampleCount} samples)'
            : 'N/A';

    final measuredFpsDisplay = diagnostics.measuredFps > 0
        ? '${diagnostics.measuredFps.toStringAsFixed(2)} FPS (${diagnostics.fpsConfidence}, ${diagnostics.fpsSampleCount} samples)'
        : 'Measuring... (${diagnostics.fpsSampleCount} samples)';

    final displayHzDisplay = '${diagnostics.displayHz.toStringAsFixed(1)} Hz';

    final matchingColor = diagnostics.frameRateMatchingStatus == 'ACTIVE'
        ? Colors.greenAccent
        : (diagnostics.frameRateMatchingStatus.startsWith('WAITING')
            ? Colors.amberAccent
            : Colors.grey);

    final videoResDisplay = diagnostics.videoWidth > 0
        ? '${diagnostics.videoWidth}x${diagnostics.videoHeight} (${diagnostics.videoMime})'
        : diagnostics.videoMime;

    final audioVolDisplay = diagnostics.deviceVolume >= 0
        ? 'Player: ${(diagnostics.playerVolume * 100).toInt()}% | Device: ${diagnostics.deviceVolume}/${diagnostics.maxDeviceVolume}'
        : 'Player: ${(diagnostics.playerVolume * 100).toInt()}%';

    final audioPipeDisplay =
        '${diagnostics.rendererStatusString} (${diagnostics.audioGroupsCount} groups)';

    return Positioned(
      top: 16,
      right: 16,
      child: IgnorePointer(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.analytics_outlined,
                      color: Color(0xFF6366F1), size: 16),
                  const SizedBox(width: 6),
                  const Text('PLAYBACK DIAGNOSTICS',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
              const Divider(color: Colors.grey, height: 12),
              _buildRow('Engine', diagnostics.engine),
              _buildRow('Media3 Ver', diagnostics.media3Version),
              _buildRow('Android API', 'API ${diagnostics.androidApiLevel}'),
              _buildRow('Video Decoder', diagnostics.decoderName),
              _buildRow('Audio Decoder', diagnostics.audioDecoderName),
              _buildRow('Video Format', videoResDisplay),
              _buildRow('Surface Path', diagnostics.surfaceType),
              _buildRow('Audio Codec',
                  '${diagnostics.audioMime} (${diagnostics.selectedAudioChannels}ch, ${diagnostics.selectedAudioSampleRate}Hz)'),
              _buildRow('Audio Lang', diagnostics.selectedAudioLanguage),
              _buildRow(
                  'Metadata FPS',
                  diagnostics.sourceFps > 0
                      ? '${diagnostics.sourceFps.toStringAsFixed(2)} FPS'
                      : 'Unknown'),
              _buildRow('Measured FPS', measuredFpsDisplay,
                  textColor: Colors.cyanAccent),
              _buildRow('Display Hz', displayHzDisplay),
              _buildRow('FR Strategy', diagnostics.frameRateStrategy),
              _buildRow('FR Matching', diagnostics.frameRateMatchingStatus,
                  textColor: matchingColor),
              _buildRow('Frames', framesDisplay,
                  textColor: diagnostics.droppedFramePercentage > 15
                      ? Colors.orangeAccent
                      : Colors.white70),
              _buildRow('Max Consec Drop',
                  '${diagnostics.maxConsecutiveDropped} (Skipped: ${diagnostics.skippedFrames})'),
              _buildRow('Pacing Offset', pacingDisplay),
              _buildRow('Audio Volume', audioVolDisplay),
              _buildRow('Audio Pipeline', audioPipeDisplay),
              _buildRow('Audio Clock',
                  diagnostics.isAudioPositionAdvancing ? "RUNNING" : "STOPPED"),
              _buildRow('Audio Underruns', '${diagnostics.audioUnderrunCount}'),
              _buildRow('Buffer',
                  '${(diagnostics.bufferDurationMs / 1000).toStringAsFixed(1)}s (Rebuffers: ${diagnostics.rebufferCount})'),
              _buildRow('Startup Time', '${diagnostics.startupTimeMs} ms'),
              _buildRow(
                  'Async Queueing',
                  diagnostics.asyncCodecQueueing
                      ? 'ACTIVE (API 23+)'
                      : 'INACTIVE'),
              _buildRow('Tunneling',
                  diagnostics.tunnelingStatus ? 'ON' : 'OFF (Safe baseline)'),
              _buildRow('Keep Screen On',
                  diagnostics.keepScreenOnStatus ? 'ACTIVE' : 'INACTIVE',
                  textColor: diagnostics.keepScreenOnStatus
                      ? Colors.greenAccent
                      : Colors.white70),
              if (diagnostics.lastAudioSinkError != 'None')
                _buildRow('AudioSink Error', diagnostics.lastAudioSinkError,
                    textColor: Colors.redAccent),
              if (diagnostics.lastAudioCodecError != 'None')
                _buildRow('AudioCodec Error', diagnostics.lastAudioCodecError,
                    textColor: Colors.redAccent),
              if (diagnostics.lastError != 'None')
                _buildRow('Last Error', diagnostics.lastError,
                    textColor: Colors.redAccent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value,
      {Color textColor = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.w500)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                  color: textColor, fontSize: 10, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
