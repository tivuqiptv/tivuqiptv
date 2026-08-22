import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'playback_diagnostics.dart';
import 'player_adapter.dart';

class FireTvMedia3PlayerAdapter implements PlayerAdapter {
  FireTvMedia3PlayerAdapter({this.diagnosticsEnabled = false}) {
    _startEventListener();
    _startPolling();
  }

  final bool diagnosticsEnabled;
  final MethodChannel _channel = const MethodChannel('com.tivuq.iptv/media3');
  final EventChannel _eventChannel =
      const EventChannel('com.tivuq.iptv/media3_events');
  StreamSubscription? _eventSub;

  final _bufferingController = StreamController<bool>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _diagnosticsController =
      StreamController<PlaybackDiagnostics>.broadcast();

  bool _isInitialized = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _pollingTimer;
  Timer? _diagnosticsTimer;
  Completer<void>? _openCompleter;
  bool _isDisposed = false;

  void _startEventListener() {
    _eventSub = _eventChannel.receiveBroadcastStream().listen((event) {
      if (_isDisposed) return;
      if (event is Map) {
        final type = event['event']?.toString();
        if (type == 'onPlaybackState') {
          final buffering = event['isBuffering'] as bool? ?? false;
          _bufferingController.add(buffering);
          final state = event['state'] as int?;
          if (state == 3 && !(_openCompleter?.isCompleted ?? true)) {
            if (!_isPlaying) {
              _isPlaying = true;
              _playingController.add(true);
            }
            _openCompleter!.complete();
          }
        } else if (type == 'onIsPlayingChanged') {
          _isPlaying = event['isPlaying'] as bool? ?? false;
          _playingController.add(_isPlaying);
        } else if (type == 'onError') {
          final message =
              event['errorMessage']?.toString() ?? 'Media3 oynatma hatası';
          if (!(_openCompleter?.isCompleted ?? true)) {
            _openCompleter!.completeError(StateError(message));
          }
        } else if (type == 'onAudioTracksChanged') {
          final tracks = event['tracks'];
          if (tracks is List && tracks.isNotEmpty) {
            final hasSupportedAudio = tracks.whereType<Map>().any(
                  (track) => track['support'] == 'FORMAT_HANDLED',
                );
            if (!hasSupportedAudio && !(_openCompleter?.isCompleted ?? true)) {
              _openCompleter!.completeError(
                UnsupportedError('UNSUPPORTED_AUDIO_CODEC'),
              );
            }
          }
        }
      }
    }, onError: (Object error) {
      if (!(_openCompleter?.isCompleted ?? true)) {
        _openCompleter!.completeError(error);
      }
    });
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final snapshot = await _channel.invokeMethod('getPlaybackSnapshot');
        if (snapshot is! Map) return;
        _position = Duration(
            milliseconds: (snapshot['positionMs'] as num?)?.toInt() ?? 0);
        _duration = Duration(
            milliseconds: (snapshot['durationMs'] as num?)?.toInt() ?? 0);
        _positionController.add(_position);
        _durationController.add(_duration);
      } catch (_) {}
    });

    if (diagnosticsEnabled) {
      _diagnosticsTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (_isDisposed) return;
        final diag = await getDiagnostics();
        _diagnosticsController.add(diag);
      });
    }
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
  Widget buildPlayerView({BoxFit fit = BoxFit.contain}) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const SizedBox.expand();
    } else {
      return const Center(
        child: Text('Native Media3 is only available on Android',
            style: TextStyle(color: Colors.white)),
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
    if (_isDisposed) return;
    if (url.trim().isEmpty) throw const FormatException('Yayın adresi boş.');

    if (!(_openCompleter?.isCompleted ?? true)) {
      _openCompleter!.complete();
    }
    final readiness = Completer<void>();
    _openCompleter = readiness;
    _bufferingController.add(true);
    try {
      await _channel.invokeMethod('openUrl', {
        'url': url,
        'userAgent': 'IPTVSmartersPlayer',
        'enableTunneling': enableTunneling,
        'quality': quality,
        'httpHeaders': httpHeaders,
      });
      await setVolume(volume);
      _isInitialized = true;
      await readiness.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () =>
            throw TimeoutException('Media3 yayın başlatma zaman aşımı'),
      );
    } catch (e) {
      debugPrint('FireTvMedia3PlayerAdapter openUrl error: $e');
      _bufferingController.add(false);
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    await _channel.invokeMethod('play');
  }

  @override
  Future<void> pause() async {
    await _channel.invokeMethod('pause');
  }

  @override
  Future<void> playOrPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> stop() async {
    if (!(_openCompleter?.isCompleted ?? true)) _openCompleter!.complete();
    await _channel.invokeMethod('stop');
  }

  @override
  Future<void> seek(Duration position) async {
    await _channel
        .invokeMethod('seek', {'positionMs': position.inMilliseconds});
  }

  @override
  Future<void> setVolume(double volume) async {
    final normalized = (volume / 100.0).clamp(0.0, 1.0);
    await _channel.invokeMethod('setVolume', {'volume': normalized});
  }

  @override
  Future<void> setTunneling(bool enabled) async {
    await _channel.invokeMethod('setTunneling', {'enabled': enabled});
  }

  @override
  Future<PlaybackDiagnostics> getDiagnostics() async {
    try {
      final res = await _channel.invokeMethod('getDiagnostics');
      if (res is Map) {
        return PlaybackDiagnostics.fromMap(res);
      }
    } catch (_) {}
    return const PlaybackDiagnostics();
  }

  @override
  Future<List<PlayerTrackOption>> getAudioTracks() async =>
      _readTracks('getAudioTracks');

  @override
  Future<List<PlayerTrackOption>> getSubtitleTracks() async =>
      _readTracks('getSubtitleTracks');

  Future<List<PlayerTrackOption>> _readTracks(String method) async {
    try {
      final result = await _channel.invokeMethod(method);
      if (result is! List) return const [];
      return result
          .whereType<Map>()
          .map((track) {
            return PlayerTrackOption(
              id: track['id']?.toString() ?? '',
              label: track['label']?.toString() ?? 'Track',
              language: track['language']?.toString(),
              isSelected: track['isSelected'] == true,
              isOff: track['isOff'] == true,
            );
          })
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
  bool get isInitialized => _isInitialized;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    if (!(_openCompleter?.isCompleted ?? true)) _openCompleter!.complete();
    _pollingTimer?.cancel();
    _diagnosticsTimer?.cancel();
    await _eventSub?.cancel();
    await _channel.invokeMethod('dispose').catchError((_) {});
    _bufferingController.close();
    _playingController.close();
    _positionController.close();
    _durationController.close();
    _diagnosticsController.close();
  }
}
