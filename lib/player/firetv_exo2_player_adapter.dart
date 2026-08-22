import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'playback_diagnostics.dart';
import 'player_adapter.dart';

class FireTvExo2PlayerAdapter implements PlayerAdapter {
  static const _channel = MethodChannel('com.tivuq.iptv/exo2');
  static const _events = EventChannel('com.tivuq.iptv/exo2_events');

  final _bufferingController = StreamController<bool>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _diagnosticsController =
      StreamController<PlaybackDiagnostics>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  Timer? _pollingTimer;
  Timer? _diagnosticsTimer;
  Timer? _audioTrackGraceTimer;
  Completer<void>? _openCompleter;
  bool _playbackReady = false;
  bool? _hasSupportedAudio;
  bool _disposed = false;
  bool _initialized = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final bool diagnosticsEnabled;

  FireTvExo2PlayerAdapter({this.diagnosticsEnabled = false}) {
    _eventSubscription = _events.receiveBroadcastStream().listen((event) {
      if (_disposed || event is! Map) return;
      final type = event['event']?.toString();
      if (type == 'onPlaybackState') {
        final buffering = event['isBuffering'] as bool? ?? false;
        _bufferingController.add(buffering);
        if (event['state'] == 3) {
          _playbackReady = true;
          if (!_playing) {
            _playing = true;
            _playingController.add(true);
          }
          _completeOpenWhenReady();
        }
      } else if (type == 'onIsPlayingChanged') {
        _playing = event['isPlaying'] as bool? ?? false;
        _playingController.add(_playing);
      } else if (type == 'onError') {
        final error = StateError(
          event['errorMessage']?.toString() ?? 'ExoPlayer2 oynatma hatası',
        );
        if (!(_openCompleter?.isCompleted ?? true)) {
          _openCompleter!.completeError(error);
        }
      } else if (type == 'onAudioTracksChanged') {
        final hasAudio = event['hasAudio'] as bool? ?? false;
        final hasSupportedAudio = event['hasSupportedAudio'] as bool? ?? false;
        _hasSupportedAudio = hasAudio ? hasSupportedAudio : null;
        _completeOpenWhenReady();
      }
    });

    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_disposed) return;
      try {
        final snapshot = await _channel.invokeMethod('getPlaybackSnapshot');
        if (snapshot is! Map) return;
        _position = Duration(
          milliseconds: (snapshot['positionMs'] as num?)?.toInt() ?? 0,
        );
        _duration = Duration(
          milliseconds: (snapshot['durationMs'] as num?)?.toInt() ?? 0,
        );
        _positionController.add(_position);
        _durationController.add(_duration);
      } catch (_) {}
    });

    if (diagnosticsEnabled) {
      _diagnosticsTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (_disposed) return;
        final diagnostics = await getDiagnostics();
        if (!_disposed) _diagnosticsController.add(diagnostics);
      });
    }
  }

  void _completeOpenWhenReady() {
    final completer = _openCompleter;
    if (!_playbackReady || completer == null || completer.isCompleted) return;

    if (_hasSupportedAudio == true) {
      _audioTrackGraceTimer?.cancel();
      completer.complete();
      return;
    }
    if (_hasSupportedAudio == false) {
      _audioTrackGraceTimer?.cancel();
      completer.completeError(UnsupportedError('UNSUPPORTED_AUDIO_CODEC'));
      return;
    }

    _audioTrackGraceTimer?.cancel();
    _audioTrackGraceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!_disposed &&
          identical(_openCompleter, completer) &&
          !completer.isCompleted) {
        // Silent channels and MPEG-TS streams with late PMT metadata are
        // valid. Fallback only after an explicit unsupported-audio event.
        completer.complete();
      }
    });
  }

  @override
  Widget buildPlayerView({BoxFit fit = BoxFit.contain}) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    // Video is rendered by a native SurfaceView below Flutter. Keeping this
    // widget transparent preserves the existing Flutter controls and animations.
    return const SizedBox.expand();
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
    _audioTrackGraceTimer?.cancel();
    _playbackReady = false;
    _hasSupportedAudio = null;
    if (!(_openCompleter?.isCompleted ?? true)) _openCompleter!.complete();
    final readiness = Completer<void>();
    _openCompleter = readiness;
    _bufferingController.add(true);
    await _channel.invokeMethod('openUrl', {
      'url': url,
      'userAgent': 'IPTVSmartersPlayer',
      'quality': quality,
      'volume': (volume / 100).clamp(0.0, 1.0),
      'enableTunneling': enableTunneling,
      'diagnosticsEnabled': diagnosticsEnabled,
      'httpHeaders': httpHeaders,
    });
    _initialized = true;
    await readiness.future.timeout(const Duration(seconds: 10));
  }

  @override
  Future<void> play() => _channel.invokeMethod('play');

  @override
  Future<void> pause() => _channel.invokeMethod('pause');

  @override
  Future<void> playOrPause() => _playing ? pause() : play();

  @override
  Future<void> stop() => _channel.invokeMethod('stop');

  @override
  Future<void> seek(Duration position) =>
      _channel.invokeMethod('seek', {'positionMs': position.inMilliseconds});

  @override
  Future<void> setVolume(double volume) => _channel.invokeMethod(
        'setVolume',
        {'volume': (volume / 100).clamp(0.0, 1.0)},
      );

  @override
  Future<void> setTunneling(bool enabled) async {}

  @override
  Future<PlaybackDiagnostics> getDiagnostics() async {
    try {
      final result = await _channel.invokeMethod('getDiagnostics');
      if (result is Map) return PlaybackDiagnostics.fromMap(result);
    } catch (_) {}
    return PlaybackDiagnostics(
      engine: 'Native ExoPlayer2 SurfaceView',
      media3Version: 'ExoPlayerLib 2.19.1 + FFmpeg audio',
      positionMs: _position.inMilliseconds,
      durationMs: _duration.inMilliseconds,
    );
  }

  @override
  Future<List<PlayerTrackOption>> getAudioTracks() =>
      _readTracks('getAudioTracks');

  @override
  Future<List<PlayerTrackOption>> getSubtitleTracks() =>
      _readTracks('getSubtitleTracks');

  Future<List<PlayerTrackOption>> _readTracks(String method) async {
    try {
      final result = await _channel.invokeMethod(method);
      if (result is! List) return const [];
      return result
          .whereType<Map>()
          .map((track) => PlayerTrackOption(
                id: track['id']?.toString() ?? '',
                label: track['label']?.toString() ?? 'Track',
                language: track['language']?.toString(),
                isSelected: track['isSelected'] == true,
                isOff: track['isOff'] == true,
              ))
          .where((track) => track.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> selectAudioTrack(String id) =>
      _channel.invokeMethod('selectAudioTrack', {'id': id});

  @override
  Future<void> selectSubtitleTrack(String id) =>
      _channel.invokeMethod('selectSubtitleTrack', {'id': id});

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
    _audioTrackGraceTimer?.cancel();
    if (!(_openCompleter?.isCompleted ?? true)) _openCompleter!.complete();
    _pollingTimer?.cancel();
    _diagnosticsTimer?.cancel();
    await _eventSubscription?.cancel();
    await _channel.invokeMethod('dispose').catchError((_) {});
    _bufferingController.close();
    _playingController.close();
    _positionController.close();
    _durationController.close();
    _diagnosticsController.close();
  }
}
