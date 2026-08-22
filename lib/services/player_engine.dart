import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:video_player/video_player.dart' as vp;

import '../player/firetv_media3_player_adapter.dart';
import '../player/firetv_exo2_player_adapter.dart';
import '../player/legacy_player_adapter.dart';
import '../player/playback_diagnostics.dart';
import '../player/player_adapter.dart';
import '../player/vlc_player_adapter.dart';
import '../providers/settings_provider.dart';

enum PlayerEngineType { exoPlayer, mediaKit, fireTvMedia3, vlc }

class AppPlayerEngine {
  static const _displayModeChannel = MethodChannel('com.tivuq.iptv/exo2');

  late PlayerAdapter _activeAdapter;
  late PlayerEngineType engineType;

  final _bufferingController = StreamController<bool>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _diagnosticsController =
      StreamController<PlaybackDiagnostics>.broadcast();
  final _adapterSubscriptions = <StreamSubscription<dynamic>>[];
  bool _isDisposed = false;
  _PlaybackRequest? _lastPlaybackRequest;

  // Legacy fields for direct access if needed by legacy callers
  vp.VideoPlayerController? get vpController =>
      (_activeAdapter is LegacyPlayerAdapter)
          ? (_activeAdapter as LegacyPlayerAdapter).legacyEngine.vpController
          : null;

  mkv.VideoController? get mkVideoController => (_activeAdapter
          is LegacyPlayerAdapter)
      ? (_activeAdapter as LegacyPlayerAdapter).legacyEngine.mkVideoController
      : null;

  PlayerAdapter get adapter => _activeAdapter;

  AppPlayerEngine({PlayerEngineType? forceEngine}) {
    engineType = _normalizeEngineForPlatform(
      forceEngine ?? _resolvePreferredEngine(),
    );
    _activeAdapter = _createAdapter(engineType);
    _bindAdapterStreams();
  }

  static PlayerEngineType _normalizeEngineForPlatform(PlayerEngineType type) {
    // AVFoundation/video_player rejects many IPTV transport streams and
    // provider-specific containers on macOS. Keep Android/Fire TV untouched
    // and use media_kit's FFmpeg pipeline only for the desktop Mac build.
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        (type == PlayerEngineType.exoPlayer ||
            type == PlayerEngineType.fireTvMedia3)) {
      return PlayerEngineType.mediaKit;
    }
    return type;
  }

  /// Whether this instance already uses the platform implementation for the
  /// requested logical engine. On macOS an Android-oriented preference is
  /// intentionally fulfilled by media_kit, so comparing enum values directly
  /// would dispose and recreate a healthy player on every channel open.
  bool usesEngine(PlayerEngineType requested) =>
      engineType == _normalizeEngineForPlatform(requested);

  static PlayerEngineType _resolvePreferredEngine() {
    final preferred = SettingsProvider().preferredEngine;
    if (preferred == 'mediaKit') return PlayerEngineType.mediaKit;
    if (preferred == 'vlc') return PlayerEngineType.vlc;
    if (preferred == 'legacy') {
      return _supportsNativeVideoPlayer
          ? PlayerEngineType.exoPlayer
          : PlayerEngineType.mediaKit;
    }
    if (preferred == 'fireTvMedia3' && _isAndroid) {
      return PlayerEngineType.fireTvMedia3;
    }
    return _supportsNativeVideoPlayer
        ? PlayerEngineType.exoPlayer
        : PlayerEngineType.mediaKit;
  }

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _supportsNativeVideoPlayer =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  PlayerAdapter _createAdapter(PlayerEngineType type) {
    if (type == PlayerEngineType.vlc) return VlcPlayerAdapter();
    if (type == PlayerEngineType.fireTvMedia3 && _isAndroid) {
      return FireTvMedia3PlayerAdapter(
        diagnosticsEnabled: SettingsProvider().showDiagnostics,
      );
    }
    if (type == PlayerEngineType.exoPlayer && _isAndroid) {
      return FireTvExo2PlayerAdapter(
        diagnosticsEnabled: SettingsProvider().showDiagnostics,
      );
    }
    return LegacyPlayerAdapter(
      engine: LegacyInternalEngine(
        forceEngine: type == PlayerEngineType.mediaKit
            ? PlayerEngineType.mediaKit
            : PlayerEngineType.exoPlayer,
      ),
    );
  }

  void _bindAdapterStreams() {
    _adapterSubscriptions.addAll([
      _activeAdapter.isBufferingStream.listen(_bufferingController.add),
      _activeAdapter.isPlayingStream.listen(_playingController.add),
      _activeAdapter.positionStream.listen(_positionController.add),
      _activeAdapter.durationStream.listen(_durationController.add),
      _activeAdapter.diagnosticsStream.listen(_diagnosticsController.add),
    ]);
  }

  Future<void> _replaceAdapter(PlayerEngineType type) async {
    for (final subscription in _adapterSubscriptions) {
      await subscription.cancel();
    }
    _adapterSubscriptions.clear();
    await _activeAdapter.dispose();
    engineType = _normalizeEngineForPlatform(type);
    _activeAdapter = _createAdapter(engineType);
    _bindAdapterStreams();
  }

  Stream<bool> get isBufferingStream => _bufferingController.stream;
  Stream<bool> get isPlayingStream => _playingController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<PlaybackDiagnostics> get diagnosticsStream =>
      _diagnosticsController.stream;

  Future<void> openUrl(
    String url, {
    double volume = 72.0,
    bool enableTunneling = false,
    String quality = 'auto',
    Map<String, String> httpHeaders = const {},
  }) async {
    if (_isDisposed) return;
    _lastPlaybackRequest = _PlaybackRequest(
      url: url,
      volume: volume,
      enableTunneling: enableTunneling,
      quality: quality,
      httpHeaders: Map<String, String>.from(httpHeaders),
    );
    final primaryEngine = engineType;
    try {
      await _activeAdapter.openUrl(
        url,
        volume: volume,
        enableTunneling: enableTunneling,
        quality: quality,
        httpHeaders: httpHeaders,
      );
      return;
    } catch (error) {
      if (error is FormatException || primaryEngine == PlayerEngineType.vlc) {
        rethrow;
      }

      final fallbackEngine = primaryEngine == PlayerEngineType.exoPlayer
          ? PlayerEngineType.fireTvMedia3
          : primaryEngine == PlayerEngineType.fireTvMedia3
              ? PlayerEngineType.exoPlayer
              : null;
      if (fallbackEngine == null) rethrow;

      debugPrint(
        '${primaryEngine.name} yayın açamadı; ${fallbackEngine.name} deneniyor: '
        '${error.runtimeType}',
      );
      await _replaceAdapter(fallbackEngine);
      await _activeAdapter.openUrl(
        url,
        volume: volume,
        enableTunneling: enableTunneling,
        quality: quality,
        httpHeaders: httpHeaders,
      );
    }
  }

  Future<void> recoverLastPlayback({bool switchNativeEngine = false}) async {
    if (_isDisposed) return;
    final request = _lastPlaybackRequest;
    if (request == null) return;
    if (switchNativeEngine && _isAndroid) {
      final fallback = engineType == PlayerEngineType.exoPlayer
          ? PlayerEngineType.fireTvMedia3
          : engineType == PlayerEngineType.fireTvMedia3
              ? PlayerEngineType.exoPlayer
              : null;
      if (fallback != null) await _replaceAdapter(fallback);
    }
    await _activeAdapter.openUrl(
      request.url,
      volume: request.volume,
      enableTunneling: request.enableTunneling,
      quality: request.quality,
      httpHeaders: request.httpHeaders,
    );
  }

  Future<void> play() async => await _activeAdapter.play();
  Future<void> pause() async => await _activeAdapter.pause();
  Future<void> playOrPause() async => await _activeAdapter.playOrPause();
  Future<void> stop() async => await _activeAdapter.stop();
  Future<void> seek(Duration position) async =>
      await _activeAdapter.seek(position);
  Future<void> setVolume(double volume) async =>
      await _activeAdapter.setVolume(volume);
  Future<void> setTunneling(bool enabled) async =>
      await _activeAdapter.setTunneling(enabled);
  static Future<void> restoreDisplayMode() async {
    try {
      await _displayModeChannel.invokeMethod('restoreDisplayMode');
    } catch (_) {}
  }

  static Future<void> setFrameRateMatchingEnabled(bool enabled) async {
    try {
      await _displayModeChannel.invokeMethod(
        'setFrameRateMatchingEnabled',
        {'enabled': enabled},
      );
    } catch (_) {}
  }

  static Future<void> restoreDisplayModeAndWait() async {
    if (!_isAndroid) return;
    await restoreDisplayMode();
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await _displayModeSnapshot();
      final displayHz = (snapshot?['displayHz'] as num?)?.toDouble() ?? 0;
      if (displayHz >= 59) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  static Future<void> prepareLiveDisplayModeAndWait({
    int refreshRate = 50,
  }) async {
    if (!_isAndroid) return;
    // Live TV is intentionally fixed to the user's selected 50/60 Hz family.
    // `prepareLiveDisplayMode` disables decoder-driven matching and applies
    // the fixed mode atomically. Calling setFrameRateMatchingEnabled(false)
    // first would restore 60 Hz briefly and then request 50 Hz, producing two
    // display transitions before the first channel opens.
    final targetRefreshRate = refreshRate == 60 ? 60 : 50;
    try {
      await _displayModeChannel.invokeMethod(
        'prepareLiveDisplayMode',
        {'refreshRate': targetRefreshRate},
      );
    } catch (_) {
      return;
    }
    await waitForVideoDisplayMode();
  }

  static Future<void> waitForVideoDisplayMode() async {
    if (!_isAndroid) return;
    final startedAt = DateTime.now();
    final deadline = startedAt.add(const Duration(seconds: 4));
    var targetObserved = false;
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await _displayModeSnapshot();
      final displayHz = (snapshot?['displayHz'] as num?)?.toDouble() ?? 0;
      final targetHz = (snapshot?['targetHz'] as num?)?.toDouble() ?? 0;
      if (snapshot?['status'] == 'UNSUPPORTED') return;
      if (targetHz > 0) {
        targetObserved = true;
        if ((displayHz - targetHz).abs() <= 0.7) return;
      } else if (!targetObserved &&
          DateTime.now().difference(startedAt) >
              const Duration(milliseconds: 700)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  static Future<Map<dynamic, dynamic>?> _displayModeSnapshot() async {
    try {
      final result =
          await _displayModeChannel.invokeMethod('getDisplayModeSnapshot');
      return result is Map ? result : null;
    } catch (_) {
      return null;
    }
  }

  Future<PlaybackDiagnostics> getDiagnostics() async =>
      await _activeAdapter.getDiagnostics();
  Future<List<PlayerTrackOption>> getAudioTracks() =>
      _activeAdapter.getAudioTracks();
  Future<List<PlayerTrackOption>> getSubtitleTracks() =>
      _activeAdapter.getSubtitleTracks();
  Future<void> selectAudioTrack(String id) =>
      _activeAdapter.selectAudioTrack(id);
  Future<void> selectSubtitleTrack(String id) =>
      _activeAdapter.selectSubtitleTrack(id);
  Future<bool> hasSelectableTracks() async {
    final results = await Future.wait([
      getAudioTracks(),
      getSubtitleTracks(),
    ]);
    return results[0].length > 1 || results[1].any((track) => !track.isOff);
  }

  bool get isInitialized => _activeAdapter.isInitialized;
  bool get isPlaying => _activeAdapter.isPlaying;
  Duration get position => _activeAdapter.position;
  Duration get duration => _activeAdapter.duration;

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final subscription in _adapterSubscriptions) {
      await subscription.cancel();
    }
    _adapterSubscriptions.clear();
    await _activeAdapter.dispose();
    _bufferingController.close();
    _playingController.close();
    _positionController.close();
    _durationController.close();
    _diagnosticsController.close();
  }
}

class _PlaybackRequest {
  const _PlaybackRequest({
    required this.url,
    required this.volume,
    required this.enableTunneling,
    required this.quality,
    required this.httpHeaders,
  });

  final String url;
  final double volume;
  final bool enableTunneling;
  final String quality;
  final Map<String, String> httpHeaders;
}

/// Legacy Internal Engine wrapper ensuring 100% safe fallback
class LegacyInternalEngine {
  static const _exo2Channel = MethodChannel('com.tivuq.iptv/exo2');
  final PlayerEngineType engineType;

  vp.VideoPlayerController? _vpController;
  mk.Player? _mkPlayer;
  mkv.VideoController? _mkVideoController;

  final _bufferingController = StreamController<bool>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();

  Stream<bool> get isBufferingStream => _bufferingController.stream;
  Stream<bool> get isPlayingStream => _playingController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;

  vp.VideoPlayerController? get vpController => _vpController;
  mkv.VideoController? get mkVideoController => _mkVideoController;

  bool _isDisposed = false;
  bool _mediaKitFrameSeen = false;
  double _lastMatchedMediaKitFps = 0;

  LegacyInternalEngine(
      {PlayerEngineType forceEngine = PlayerEngineType.exoPlayer})
      : engineType = forceEngine {
    if (engineType == PlayerEngineType.mediaKit) {
      _mkPlayer = mk.Player(
        configuration: const mk.PlayerConfiguration(
          bufferSize: 64 * 1024 * 1024,
          logLevel: mk.MPVLogLevel.warn,
        ),
      );
      _mkVideoController = mkv.VideoController(
        _mkPlayer!,
        configuration: mkv.VideoControllerConfiguration(
          // macOS'ta `gpu` MPV'nin ayrı bir native pencere oluşturmasına
          // neden olur. `libmpv` görüntüyü Flutter içindeki mevcut video
          // alanına gömer. Android'in kanıtlanmış yolu aynen korunur.
          vo: !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
              ? 'libmpv'
              : 'gpu',
          hwdec: !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
              // Bazı IPTV H.264 profilleri macOS VideoToolbox tarafından
              // reddediliyor ve ses başlasa bile video karesi oluşmuyor.
              // Mac masaüstünde FFmpeg yazılım çözücüsü bu farklı
              // profilleri daha güvenilir oynatıyor. Android yolu değişmez.
              ? 'no'
              : 'mediacodec-copy',
          enableHardwareAcceleration: true,
          androidAttachSurfaceAfterVideoParameters:
              !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
        ),
      );

      _mkPlayer!.stream.buffering.listen((b) {
        if (!_isDisposed) _bufferingController.add(b);
      });
      _mkPlayer!.stream.playing.listen((p) {
        if (!_isDisposed) {
          _playingController.add(p);
          if (p) {
            _mediaKitFrameSeen = true;
            _bufferingController.add(false);
          }
        }
      });
      _mkPlayer!.stream.position.listen((pos) {
        if (!_isDisposed) {
          _positionController.add(pos);
          if (!_mediaKitFrameSeen && pos > Duration.zero) {
            _mediaKitFrameSeen = true;
            _bufferingController.add(false);
          }
        }
      });
      _mkPlayer!.stream.videoParams.listen((params) {
        if (!_isDisposed && ((params.dw ?? 0) > 0 || (params.dh ?? 0) > 0)) {
          _mediaKitFrameSeen = true;
          _bufferingController.add(false);
        }
      });
      _mkPlayer!.stream.duration.listen((dur) {
        if (!_isDisposed) _durationController.add(dur);
      });
      _mkPlayer!.stream.track.listen((track) {
        _matchMediaKitFrameRate(track.video.fps);
      });
    }
  }

  void _matchMediaKitFrameRate(double? fps) {
    if (_isDisposed || fps == null || fps <= 0) return;
    if ((fps - _lastMatchedMediaKitFps).abs() < 0.5) return;
    _lastMatchedMediaKitFps = fps;
    _exo2Channel.invokeMethod('matchDisplayFrameRate', {'fps': fps});
  }

  Future<void> openUrl(
    String url, {
    double volume = 72.0,
    Map<String, String> httpHeaders = const {},
  }) async {
    if (_isDisposed) return;
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    if (engineType == PlayerEngineType.exoPlayer) {
      _bufferingController.add(true);
      if (_vpController != null) {
        await _vpController!.dispose();
        _vpController = null;
      }
      try {
        final uri = Uri.parse(cleanUrl);

        vp.VideoFormat? formatHint;
        if (cleanUrl.toLowerCase().contains('.m3u8') ||
            cleanUrl.toLowerCase().contains('type=m3u8')) {
          formatHint = vp.VideoFormat.hls;
        }

        _vpController = vp.VideoPlayerController.networkUrl(
          uri,
          formatHint: formatHint,
          httpHeaders: {
            'User-Agent': 'IPTVSmartersPlayer',
            'Accept': '*/*',
            ...httpHeaders,
          },
          videoPlayerOptions: vp.VideoPlayerOptions(
            mixWithOthers: false,
            allowBackgroundPlayback: false,
          ),
        );

        bool? lastBuffering;
        bool? lastPlaying;

        _vpController!.addListener(() {
          if (_isDisposed || _vpController == null) return;
          final value = _vpController!.value;

          if (lastBuffering != value.isBuffering) {
            lastBuffering = value.isBuffering;
            _bufferingController.add(value.isBuffering);
          }

          if (lastPlaying != value.isPlaying) {
            lastPlaying = value.isPlaying;
            _playingController.add(value.isPlaying);
          }

          _positionController.add(value.position);
          _durationController.add(value.duration);
        });

        await _vpController!.initialize();
        await _vpController!.setVolume((volume / 100.0).clamp(0.0, 1.0));
        await _vpController!.play();
        _bufferingController.add(false);
      } catch (e) {
        debugPrint('Legacy ExoPlayer openUrl error: $e');
        _bufferingController.add(false);
        rethrow;
      }
    } else {
      try {
        _mediaKitFrameSeen = false;
        _lastMatchedMediaKitFps = 0;
        _bufferingController.add(true);
        await _mkPlayer!.open(
          mk.Media(
            cleanUrl,
            httpHeaders: {
              'User-Agent': 'IPTVSmartersPlayer',
              'Accept': '*/*',
              ...httpHeaders,
            },
          ),
        );
        await _mkPlayer!.setVolume(volume);
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
          await _waitForMacMediaKitPlayback();
        } else {
          try {
            await _mkVideoController!.waitUntilFirstFrameRendered.timeout(
              const Duration(seconds: 8),
            );
          } catch (_) {}
        }
        _mediaKitFrameSeen = true;
        _bufferingController.add(false);
        _matchMediaKitFrameRate(_mkPlayer!.state.track.video.fps);
      } catch (e) {
        debugPrint('Legacy MediaKit openUrl error: $e');
        _bufferingController.add(false);
        rethrow;
      }
    }
  }

  Future<void> _waitForMacMediaKitPlayback() async {
    final player = _mkPlayer!;
    final videoController = _mkVideoController!;

    bool isPlaybackReady() {
      final state = player.state;
      final hasDim = (state.width ?? state.videoParams.dw ?? 0) > 0 &&
          (state.height ?? state.videoParams.dh ?? 0) > 0;
      final hasPos = state.position > Duration.zero;
      final hasTracks =
          state.tracks.video.isNotEmpty || state.tracks.audio.isNotEmpty;
      return hasDim || hasPos || hasTracks || state.playing;
    }

    if (isPlaybackReady()) return;

    try {
      await Future.any<void>([
        videoController.waitUntilFirstFrameRendered,
        player.stream.videoParams
            .firstWhere(
                (params) => (params.dw ?? 0) > 0 && (params.dh ?? 0) > 0)
            .then<void>((_) {}),
        player.stream.position
            .firstWhere((position) => position > Duration.zero)
            .then<void>((_) {}),
        player.stream.playing
            .firstWhere((playing) => playing)
            .then<void>((_) {}),
        player.stream.tracks
            .firstWhere(
                (tracks) => tracks.video.isNotEmpty || tracks.audio.isNotEmpty)
            .then<void>((_) {}),
      ]).timeout(const Duration(seconds: 8));
    } catch (_) {
      debugPrint(
          'MediaKit playback startup wait completed via background stream.');
    }
  }

  Future<void> play() async {
    if (_isDisposed) return;
    if (engineType == PlayerEngineType.exoPlayer) {
      await _vpController?.play();
    } else {
      await _mkPlayer?.play();
    }
  }

  Future<void> pause() async {
    if (_isDisposed) return;
    if (engineType == PlayerEngineType.exoPlayer) {
      await _vpController?.pause();
    } else {
      await _mkPlayer?.pause();
    }
  }

  Future<void> playOrPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop() async {
    if (_isDisposed) return;
    if (engineType == PlayerEngineType.exoPlayer) {
      await _vpController?.pause();
    } else {
      await _mkPlayer?.stop();
    }
  }

  Future<void> seek(Duration position) async {
    if (_isDisposed) return;
    if (engineType == PlayerEngineType.exoPlayer) {
      await _vpController?.seekTo(position);
    } else {
      await _mkPlayer?.seek(position);
    }
  }

  Future<void> setVolume(double volume) async {
    if (_isDisposed) return;
    if (engineType == PlayerEngineType.exoPlayer) {
      await _vpController?.setVolume((volume / 100.0).clamp(0.0, 1.0));
    } else {
      await _mkPlayer?.setVolume(volume);
    }
  }

  Future<List<PlayerTrackOption>> getAudioTracks() async {
    final player = _mkPlayer;
    if (engineType != PlayerEngineType.mediaKit || player == null) {
      return const [];
    }
    final selectedId = player.state.track.audio.id;
    return player.state.tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .map((track) => PlayerTrackOption(
              id: track.id,
              label: track.title?.trim().isNotEmpty == true
                  ? track.title!.trim()
                  : (track.language?.toUpperCase() ?? 'Audio'),
              language: track.language,
              isSelected: track.id == selectedId,
            ))
        .toList(growable: false);
  }

  Future<List<PlayerTrackOption>> getSubtitleTracks() async {
    final player = _mkPlayer;
    if (engineType != PlayerEngineType.mediaKit || player == null) {
      return const [];
    }
    final actual = player.state.tracks.subtitle
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList(growable: false);
    if (actual.isEmpty) return const [];
    final selectedId = player.state.track.subtitle.id;
    return [
      PlayerTrackOption(
        id: 'no',
        label: 'Off',
        isSelected: selectedId == 'no',
        isOff: true,
      ),
      ...actual.map((track) => PlayerTrackOption(
            id: track.id,
            label: track.title?.trim().isNotEmpty == true
                ? track.title!.trim()
                : (track.language?.toUpperCase() ?? 'Subtitle'),
            language: track.language,
            isSelected: track.id == selectedId,
          )),
    ];
  }

  Future<void> selectAudioTrack(String id) async {
    final player = _mkPlayer;
    if (engineType != PlayerEngineType.mediaKit || player == null) return;
    final matches = player.state.tracks.audio.where((track) => track.id == id);
    if (matches.isNotEmpty) await player.setAudioTrack(matches.first);
  }

  Future<void> selectSubtitleTrack(String id) async {
    final player = _mkPlayer;
    if (engineType != PlayerEngineType.mediaKit || player == null) return;
    if (id == 'no') {
      await player.setSubtitleTrack(mk.SubtitleTrack.no());
      return;
    }
    final matches =
        player.state.tracks.subtitle.where((track) => track.id == id);
    if (matches.isNotEmpty) await player.setSubtitleTrack(matches.first);
  }

  bool get isInitialized {
    if (engineType == PlayerEngineType.exoPlayer) {
      return _vpController != null && _vpController!.value.isInitialized;
    } else {
      return _mkPlayer != null;
    }
  }

  bool get isPlaying {
    if (engineType == PlayerEngineType.exoPlayer) {
      return _vpController?.value.isPlaying ?? false;
    } else {
      return _mkPlayer?.state.playing ?? false;
    }
  }

  Duration get position {
    if (engineType == PlayerEngineType.exoPlayer) {
      return _vpController?.value.position ?? Duration.zero;
    } else {
      return _mkPlayer?.state.position ?? Duration.zero;
    }
  }

  Duration get duration {
    if (engineType == PlayerEngineType.exoPlayer) {
      return _vpController?.value.duration ?? Duration.zero;
    } else {
      return _mkPlayer?.state.duration ?? Duration.zero;
    }
  }

  Future<void> dispose() async {
    _isDisposed = true;
    _bufferingController.close();
    _playingController.close();
    _positionController.close();
    _durationController.close();
    await _vpController?.dispose();
    await _mkPlayer?.dispose();
  }
}
