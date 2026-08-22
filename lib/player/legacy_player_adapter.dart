import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../services/player_engine.dart';
import 'playback_diagnostics.dart';
import 'player_adapter.dart';

import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:video_player/video_player.dart' as vp;

class LegacyPlayerAdapter implements PlayerAdapter {
  static const _channel = MethodChannel('com.tivuq.iptv/media3');
  final LegacyInternalEngine _legacyEngine;
  final _diagnosticsController =
      StreamController<PlaybackDiagnostics>.broadcast();

  LegacyInternalEngine get legacyEngine => _legacyEngine;

  LegacyPlayerAdapter({LegacyInternalEngine? engine})
      : _legacyEngine = engine ?? LegacyInternalEngine();

  @override
  Stream<bool> get isBufferingStream => _legacyEngine.isBufferingStream;

  @override
  Stream<bool> get isPlayingStream => _legacyEngine.isPlayingStream;

  @override
  Stream<Duration> get positionStream => _legacyEngine.positionStream;

  @override
  Stream<Duration> get durationStream => _legacyEngine.durationStream;

  @override
  Stream<PlaybackDiagnostics> get diagnosticsStream =>
      _diagnosticsController.stream;

  void _setKeepScreenOn(bool enabled) {
    // This native method belongs to the Android Media3 host. Calling it on
    // macOS returns an asynchronous MissingPluginException; a synchronous
    // try/catch cannot catch that Future error.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(
      _channel.invokeMethod<void>(
          'setKeepScreenOn', {'enabled': enabled}).catchError((_) {}),
    );
  }

  @override
  Widget buildPlayerView({BoxFit fit = BoxFit.contain}) {
    if (_legacyEngine.engineType == PlayerEngineType.exoPlayer) {
      final vpController = _legacyEngine.vpController;
      if (vpController == null ||
          !vpController.value.isInitialized ||
          vpController.value.hasError) {
        return const SizedBox.shrink();
      }
      return FittedBox(
        fit: fit,
        child: SizedBox(
          width: vpController.value.size.width > 0
              ? vpController.value.size.width
              : 1920,
          height: vpController.value.size.height > 0
              ? vpController.value.size.height
              : 1080,
          child: vp.VideoPlayer(vpController),
        ),
      );
    } else {
      final mkController = _legacyEngine.mkVideoController;
      if (mkController == null) {
        return const SizedBox.shrink();
      }
      return mkv.Video(
        controller: mkController,
        fit: fit,
        controls: mkv.NoVideoControls,
      );
    }
  }

  @override
  Future<void> openUrl(
    String url, {
    double volume = 72.0,
    bool enableTunneling = false,
    String quality = 'auto',
    Map<String, String> httpHeaders = const {},
  }) async {
    await _legacyEngine.openUrl(url, volume: volume, httpHeaders: httpHeaders);
    _setKeepScreenOn(true);
  }

  @override
  Future<void> play() async {
    await _legacyEngine.play();
    _setKeepScreenOn(true);
  }

  @override
  Future<void> pause() async {
    await _legacyEngine.pause();
    _setKeepScreenOn(false);
  }

  @override
  Future<void> playOrPause() async {
    await _legacyEngine.playOrPause();
    _setKeepScreenOn(_legacyEngine.isPlaying);
  }

  @override
  Future<void> stop() async {
    await _legacyEngine.stop();
    _setKeepScreenOn(false);
  }

  @override
  Future<void> seek(Duration position) async =>
      await _legacyEngine.seek(position);

  @override
  Future<void> setVolume(double volume) async =>
      await _legacyEngine.setVolume(volume);

  @override
  Future<void> setTunneling(bool enabled) async {}

  @override
  Future<PlaybackDiagnostics> getDiagnostics() async {
    return PlaybackDiagnostics(
      engine: 'Legacy (${_legacyEngine.engineType.name})',
      media3Version: 'Transitive 1.5.1',
      decoderName: 'MediaCodec (Legacy)',
      isHardwareDecoder: true,
      videoMime: 'video/avc',
      audioMime: 'audio/mp4a-latm',
      positionMs: _legacyEngine.position.inMilliseconds,
      durationMs: _legacyEngine.duration.inMilliseconds,
      keepScreenOnStatus: _legacyEngine.isPlaying,
    );
  }

  @override
  Future<List<PlayerTrackOption>> getAudioTracks() =>
      _legacyEngine.getAudioTracks();

  @override
  Future<List<PlayerTrackOption>> getSubtitleTracks() =>
      _legacyEngine.getSubtitleTracks();

  @override
  Future<void> selectAudioTrack(String id) =>
      _legacyEngine.selectAudioTrack(id);

  @override
  Future<void> selectSubtitleTrack(String id) =>
      _legacyEngine.selectSubtitleTrack(id);

  @override
  bool get isInitialized => _legacyEngine.isInitialized;

  @override
  bool get isPlaying => _legacyEngine.isPlaying;

  @override
  Duration get position => _legacyEngine.position;

  @override
  Duration get duration => _legacyEngine.duration;

  @override
  Future<void> dispose() async {
    _setKeepScreenOn(false);
    _diagnosticsController.close();
    await _legacyEngine.dispose();
  }
}
