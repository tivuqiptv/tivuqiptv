import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import 'playback_diagnostics.dart';
import 'player_adapter.dart';

class VlcPlayerAdapter implements PlayerAdapter {
  static const _screenChannel = MethodChannel('com.tivuq.iptv/media3');

  final _bufferingController = StreamController<bool>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _diagnosticsController =
      StreamController<PlaybackDiagnostics>.broadcast();

  VlcPlayerController? _controller;
  Completer<void>? _openCompleter;
  bool _disposed = false;
  bool _initialized = false;
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  void _onControllerChanged() {
    if (_disposed || _controller == null) return;
    final value = _controller!.value;
    _initialized = value.isInitialized;
    _playing = value.isPlaying;
    _buffering = value.isBuffering;
    _position = value.position;
    _duration = value.duration;
    _bufferingController.add(_buffering);
    _playingController.add(_playing);
    _positionController.add(_position);
    _durationController.add(_duration);

    final completer = _openCompleter;
    if (value.hasError && completer != null && !completer.isCompleted) {
      completer.completeError(StateError(value.errorDescription));
    } else if (value.isPlaying && completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  @override
  Widget buildPlayerView({BoxFit fit = BoxFit.contain}) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    final aspectRatio = controller.value.aspectRatio > 1
        ? controller.value.aspectRatio
        : 16 / 9;
    return ClipRect(
      child: FittedBox(
        fit: fit,
        child: SizedBox(
          width: 1920,
          height: 1920 / aspectRatio,
          child: VlcPlayer(
            controller: controller,
            aspectRatio: aspectRatio,
            virtualDisplay: false,
          ),
        ),
      ),
    );
  }

  @override
  Future<void> openUrl(
    String url, {
    double volume = 72,
    bool enableTunneling = false,
    String quality = 'auto',
    Map<String, String> httpHeaders = const {},
  }) async {
    if (_disposed) return;
    if (url.trim().isEmpty) throw const FormatException('Yayın adresi boş.');

    final oldController = _controller;
    if (oldController != null) {
      oldController.removeListener(_onControllerChanged);
      await oldController.dispose();
    }
    if (!(_openCompleter?.isCompleted ?? true)) _openCompleter!.complete();

    _initialized = false;
    _playing = false;
    _buffering = true;
    _bufferingController.add(true);
    final readiness = Completer<void>();
    _openCompleter = readiness;
    _controller = VlcPlayerController.network(
      url.trim(),
      hwAcc: HwAcc.full,
      autoInitialize: true,
      autoPlay: true,
      allowBackgroundPlayback: false,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions([
          VlcAdvancedOptions.networkCaching(1500),
          VlcAdvancedOptions.clockJitter(0),
        ]),
        http: VlcHttpOptions([
          VlcHttpOptions.httpReconnect(true),
          VlcHttpOptions.httpUserAgent('IPTVSmartersPlayer'),
        ]),
        video: VlcVideoOptions([
          VlcVideoOptions.dropLateFrames(true),
          VlcVideoOptions.skipFrames(true),
        ]),
      ),
    )..addListener(_onControllerChanged);

    await readiness.future.timeout(const Duration(seconds: 20));
    await _controller!.setVolume(volume.round().clamp(0, 100));
    _screenChannel.invokeMethod('setKeepScreenOn', {'enabled': true});
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> playOrPause() async => _playing ? pause() : play();

  @override
  Future<void> stop() async => _controller?.stop();

  @override
  Future<void> seek(Duration position) async => _controller?.seekTo(position);

  @override
  Future<void> setVolume(double volume) async =>
      _controller?.setVolume(volume.round().clamp(0, 100));

  @override
  Future<void> setTunneling(bool enabled) async {}

  @override
  Future<PlaybackDiagnostics> getDiagnostics() async => PlaybackDiagnostics(
        engine: 'VLC (manuel)',
        media3Version: 'libVLC',
        decoderName: 'MediaCodec + libVLC',
        audioDecoderName: 'libVLC/FFmpeg',
        isHardwareDecoder: true,
        isDecoderVerified: _initialized,
        positionMs: _position.inMilliseconds,
        durationMs: _duration.inMilliseconds,
        keepScreenOnStatus: _playing,
      );

  @override
  Future<List<PlayerTrackOption>> getAudioTracks() async {
    final controller = _controller;
    if (controller == null || !_initialized) return const [];
    try {
      final tracks = await controller.getAudioTracks();
      final selected = await controller.getAudioTrack();
      return tracks.entries
          .map((entry) => PlayerTrackOption(
                id: '${entry.key}',
                label: entry.value,
                isSelected: entry.key == selected,
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<PlayerTrackOption>> getSubtitleTracks() async {
    final controller = _controller;
    if (controller == null || !_initialized) return const [];
    try {
      final tracks = await controller.getSpuTracks();
      final selected = await controller.getSpuTrack();
      final options = tracks.entries
          .map((entry) => PlayerTrackOption(
                id: '${entry.key}',
                label: entry.key == -1 ? 'Off' : entry.value,
                isSelected: entry.key == selected,
                isOff: entry.key == -1,
              ))
          .toList(growable: false);
      if (options.every((track) => !track.isOff)) {
        return [
          PlayerTrackOption(
            id: '-1',
            label: 'Off',
            isSelected: selected == -1,
            isOff: true,
          ),
          ...options,
        ];
      }
      return options;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> selectAudioTrack(String id) async {
    await _controller?.setAudioTrack(int.tryParse(id) ?? -1);
  }

  @override
  Future<void> selectSubtitleTrack(String id) async {
    await _controller?.setSpuTrack(int.tryParse(id) ?? -1);
  }

  @override
  Stream<bool> get isBufferingStream => _bufferingController.stream;
  @override
  Stream<bool> get isPlayingStream => _playingController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration> get durationStream => _durationController.stream;
  @override
  Stream<PlaybackDiagnostics> get diagnosticsStream =>
      _diagnosticsController.stream;
  @override
  bool get isInitialized => _initialized;
  @override
  bool get isPlaying => _playing;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!(_openCompleter?.isCompleted ?? true)) _openCompleter!.complete();
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onControllerChanged);
    if (controller != null) {
      try {
        await controller.stop();
      } catch (_) {}
      await controller.dispose();
    }
    await _screenChannel
        .invokeMethod('setKeepScreenOn', {'enabled': false}).catchError((_) {});
    _bufferingController.close();
    _playingController.close();
    _positionController.close();
    _durationController.close();
    _diagnosticsController.close();
  }
}
