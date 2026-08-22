import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/player_engine.dart';
import '../services/local_companion_service.dart';
import '../widgets/app_video_widget.dart';
import '../widgets/settings_overlay.dart';
import '../providers/settings_provider.dart';
import '../providers/watch_history_provider.dart';
import '../models/channel.dart';
import '../utils/instant_dialog.dart';
import 'package:provider/provider.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String profileId;
  final String? subtitle;
  final Map<String, String> httpHeaders;

  // Dizi/Playlist desteği için
  final List<Channel>? playlist;
  final int? initialIndex;
  final String? historyGroupId;
  final int? historyGroupItemCount;
  final int historyGroupIndexOffset;

  const VideoPlayerScreen({
    super.key,
    required this.url,
    required this.title,
    required this.profileId,
    this.subtitle,
    this.httpHeaders = const {},
    this.playlist,
    this.initialIndex,
    this.historyGroupId,
    this.historyGroupItemCount,
    this.historyGroupIndexOffset = 0,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  late AppPlayerEngine _playerEngine;

  bool _showControls = true;
  Timer? _hideControlsTimer;
  double _volume = 72.0;
  final double _brightness = 1.0;
  final bool _isDragging = false;
  bool _showSettings = false;
  bool _isPlaying = false;
  StreamSubscription<bool>? _playingSubscription;
  DateTime? _settingsClosedAt;
  bool _blockBackUntilRelease = false;
  bool _playerBackArmed = true;
  Timer? _backReleaseFallback;
  late final SettingsProvider _settings;
  late final WatchHistoryProvider _history;

  final FocusNode _keyboardFocusNode = FocusNode();
  bool _showVolumeIndicator = false;
  Timer? _volumeIndicatorTimer;
  double _lastNonZeroVolume = 72.0;

  // Dizi Oynatma Durumu
  late int _currentIndex;
  late String _currentUrl;
  late String _currentTitle;
  late Map<String, String> _currentHeaders;

  // Progress tracker timer
  Timer? _progressTimer;

  // UI Odaklanma (Controls açıkken)
  bool _uiFocused = false;
  String _focusedControl = 'play'; // 'prev', 'play', 'next'
  LogicalKeyboardKey? _activeSeekKey;
  int _seekRepeatCount = 0;
  bool _fastSeekMode = false;
  bool _resumeAfterFastSeek = false;
  Duration? _scrubPreviewPosition;
  bool _videoSurfaceVisible = false;
  bool _isExiting = false;
  bool _engineDisposed = false;
  bool _resumePlaybackAfterLifecyclePause = false;
  int _playbackGeneration = 0;
  final Set<String> _markedWatchedIds = <String>{};

  @override
  void initState() {
    super.initState();
    LocalCompanionService.vodPlaybackDepth.value++;
    WidgetsBinding.instance.addObserver(this);
    _settings = Provider.of<SettingsProvider>(context, listen: false);
    _history = Provider.of<WatchHistoryProvider>(context, listen: false);
    _playerEngine = AppPlayerEngine(forceEngine: _vodEngineType);
    _bindPlayingState();

    _currentIndex = widget.initialIndex ?? 0;
    _currentUrl = widget.url;
    _currentTitle = widget.title;
    _currentHeaders = Map<String, String>.from(widget.httpHeaders);

    _initPlayer(_currentUrl);
  }

  PlayerEngineType get _vodEngineType {
    switch (_settings.vodPreferredEngine) {
      case 'vlc':
        return PlayerEngineType.vlc;
      case 'fireTvMedia3':
        return PlayerEngineType.fireTvMedia3;
      default:
        return PlayerEngineType.exoPlayer;
    }
  }

  Future<void> _applyVodEnginePreference() async {
    final target = _vodEngineType;
    if (_playerEngine.usesEngine(target)) return;
    await _playerEngine.dispose();
    if (!mounted) return;
    setState(() {
      _playerEngine = AppPlayerEngine(forceEngine: target);
    });
    _bindPlayingState();
    _initPlayer(_currentUrl);
  }

  void _bindPlayingState() {
    unawaited(_playingSubscription?.cancel());
    _playingSubscription = _playerEngine.isPlayingStream.listen((playing) {
      if (!mounted) return;
      setState(() {
        _isPlaying = playing;
        if (!playing) _showControls = true;
      });
      if (playing) {
        _markCurrentContentWatched();
        _startHideControlsTimer();
      } else {
        _hideControlsTimer?.cancel();
      }
    });
  }

  void _markCurrentContentWatched() {
    if (!_markedWatchedIds.add(_currentUrl)) return;
    unawaited(
      _history.markWatched(_currentUrl, profileId: widget.profileId),
    );
    final groupId = widget.historyGroupId;
    if (groupId != null && _markedWatchedIds.add(groupId)) {
      unawaited(_history.markWatched(groupId, profileId: widget.profileId));
    }
  }

  Future<void> _initPlayer(String streamUrl) async {
    final generation = ++_playbackGeneration;
    if (mounted) setState(() => _videoSurfaceVisible = false);
    // Film ve diziler sabit 60 Hz'de oynar. Oynatıcı formatı birkaç saniye
    // sonra öğrendiğinde yeniden ekran modu istemesine izin verme; aksi halde
    // Fire TV HDMI el sıkışmasını tekrar gösterir.
    await AppPlayerEngine.setFrameRateMatchingEnabled(false);
    await AppPlayerEngine.restoreDisplayModeAndWait();
    if (!mounted || generation != _playbackGeneration || _isExiting) return;
    final openFuture = _playerEngine.openUrl(
      streamUrl,
      volume: _volume,
      enableTunneling: _settings.enableTunneling,
      quality: _settings.quality,
      httpHeaders: _currentHeaders,
    );

    // Geçmişten süreyi al — media_kit'te seek için önce oynatma başlamalı
    final pastHistory = _history.getProgress(
      streamUrl,
      profileId: widget.profileId,
    );
    if (pastHistory != null &&
        pastHistory.position > 0 &&
        !pastHistory.isCompleted) {
      // İlk 'playing' eventi gelince seek yap
      late StreamSubscription<bool> sub;
      sub = _playerEngine.isPlayingStream.listen((isPlaying) {
        if (isPlaying) {
          _playerEngine.seek(Duration(seconds: pastHistory.position));
          sub.cancel();
        }
      });
    }

    try {
      await openFuture;
      if (mounted && generation == _playbackGeneration && !_isExiting) {
        setState(() => _videoSurfaceVisible = true);
      }
    } catch (_) {
      if (mounted && generation == _playbackGeneration && !_isExiting) {
        setState(() => _videoSurfaceVisible = true);
      }
    }

    _startHideControlsTimer();
    _startProgressTracker();
  }

  void _startProgressTracker() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _saveCurrentProgress();
    });
  }

  void _playNextEpisode() {
    if (widget.playlist != null &&
        _currentIndex < widget.playlist!.length - 1) {
      _saveCurrentProgress();
      setState(() {
        _currentIndex++;
        final nextEp = widget.playlist![_currentIndex];
        _currentUrl = nextEp.url;
        _currentTitle = nextEp.name;
        _currentHeaders = Map<String, String>.from(nextEp.httpHeaders);
        _initPlayer(_currentUrl);
        _showControlsTemporarily();
        _focusedControl = 'play';
      });
    } else {
      // Son bölümse veya playlist yoksa çık
      unawaited(_exitPlayer());
    }
  }

  void _playPrevEpisode() {
    if (widget.playlist != null && _currentIndex > 0) {
      _saveCurrentProgress();
      setState(() {
        _currentIndex--;
        final prevEp = widget.playlist![_currentIndex];
        _currentUrl = prevEp.url;
        _currentTitle = prevEp.name;
        _currentHeaders = Map<String, String>.from(prevEp.httpHeaders);
        _initPlayer(_currentUrl);
        _showControlsTemporarily();
        _focusedControl = 'play';
      });
    }
  }

  bool get _hasNext =>
      widget.playlist != null && _currentIndex < widget.playlist!.length - 1;
  bool get _hasPrev => widget.playlist != null && _currentIndex > 0;

  void _saveCurrentProgress() {
    final pos = _playerEngine.position.inSeconds;
    final dur = _playerEngine.duration.inSeconds;
    if (dur > 0 && pos > 0) {
      _history.saveProgress(_currentUrl, pos, dur, profileId: widget.profileId);
      final groupId = widget.historyGroupId;
      final itemCount = widget.historyGroupItemCount ?? 0;
      if (groupId != null && itemCount > 0) {
        final episodeFraction = (pos / dur).clamp(0.0, 1.0);
        final groupPosition =
            widget.historyGroupIndexOffset + _currentIndex + episodeFraction;
        final existing = _history
                .getProgress(groupId, profileId: widget.profileId)
                ?.percent ??
            0.0;
        final newProgress = (groupPosition / itemCount).clamp(0.0, 1.0);
        // Eski bir bölümü tekrar açmak, dizinin daha önce ulaşılan genel
        // ilerlemesini geriye düşürmesin.
        if (newProgress >= existing) {
          _history.saveProgress(
            groupId,
            (newProgress * 10000).round(),
            10000,
            profileId: widget.profileId,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveCurrentProgress();
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    _volumeIndicatorTimer?.cancel();
    _backReleaseFallback?.cancel();
    unawaited(_playingSubscription?.cancel());
    _keyboardFocusNode.dispose();
    final cleanup = _engineDisposed
        ? Future<void>.value()
        : _disposePlayerAndRestoreDisplay();
    unawaited(cleanup.whenComplete(() {
      final depth = LocalCompanionService.vodPlaybackDepth.value;
      LocalCompanionService.vodPlaybackDepth.value = depth > 0 ? depth - 1 : 0;
    }));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _resumePlaybackAfterLifecyclePause = _isPlaying;
      unawaited(_playerEngine.pause());
    } else if (state == AppLifecycleState.resumed) {
      if (_resumePlaybackAfterLifecyclePause && !_isExiting) {
        unawaited(_playerEngine.play());
      }
      _resumePlaybackAfterLifecyclePause = false;
    }
  }

  Future<void> _disposePlayerAndRestoreDisplay() async {
    final keepLiveTvDisplayMode =
        LocalCompanionService.liveTvTransitionInProgress;
    await _playerEngine.dispose();
    _engineDisposed = true;
    if (keepLiveTvDisplayMode) return;
    await AppPlayerEngine.setFrameRateMatchingEnabled(true);
    await AppPlayerEngine.restoreDisplayMode();
  }

  Future<void> _exitPlayer() async {
    if (_isExiting) return;
    _isExiting = true;
    _playbackGeneration++;
    _saveCurrentProgress();
    if (mounted) setState(() => _videoSurfaceVisible = false);
    if (!_engineDisposed) {
      await _playerEngine.dispose();
      _engineDisposed = true;
    }
    if (!LocalCompanionService.liveTvTransitionInProgress) {
      await AppPlayerEngine.setFrameRateMatchingEnabled(true);
      await AppPlayerEngine.restoreDisplayModeAndWait();
    }
    if (mounted) Navigator.pop(context);
  }

  void _adjustVolume(double delta) {
    final newVol = (_volume + delta).clamp(0.0, 100.0);
    _setVolume(newVol);
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      if (value > 0) _lastNonZeroVolume = value;
    });
    _playerEngine.setVolume(value);
    _showVolumeHUDTemp();
  }

  void _toggleMute() {
    if (_volume > 0) {
      _lastNonZeroVolume = _volume;
      _setVolume(0);
    } else {
      _setVolume(_lastNonZeroVolume);
    }
  }

  void _showVolumeHUDTemp() {
    setState(() => _showVolumeIndicator = true);
    _volumeIndicatorTimer?.cancel();
    _volumeIndicatorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showVolumeIndicator = false);
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (!_isPlaying) return;
    if (_settings.autoHideDuration == 0.0) return;
    _hideControlsTimer = Timer(
      Duration(milliseconds: (_settings.autoHideDuration * 1000).toInt()),
      () {
        if (mounted && !_isDragging && !_showSettings) {
          setState(() {
            _showControls = false;
            _uiFocused = false;
          });
        }
      },
    );
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) _uiFocused = false;
    });
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _showControlsTemporarily() {
    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
    }
    _startHideControlsTimer();
  }

  void _togglePlayback() {
    _playerEngine.playOrPause();
    _showControlsTemporarily();
  }

  void _seekRelative(Duration offset) {
    final target = _playerEngine.position + offset;
    _playerEngine.seek(target < Duration.zero ? Duration.zero : target);
    _showControlsTemporarily();
  }

  void _focusBottomControl(String control) {
    setState(() {
      _showControls = true;
      _uiFocused = true;
      _focusedControl = control;
    });
    _startHideControlsTimer();
  }

  void _moveBottomControl(int delta) {
    const controls = ['rewind', 'play', 'forward'];
    var index = controls.indexOf(_focusedControl);
    if (index < 0) index = 1;
    index = (index + delta).clamp(0, controls.length - 1);
    _focusBottomControl(controls[index]);
  }

  void _activateFocusedControl() {
    switch (_focusedControl) {
      case 'rewind':
        _seekRelative(const Duration(seconds: -10));
        break;
      case 'forward':
        _seekRelative(const Duration(seconds: 10));
        break;
      case 'timeline':
        _togglePlayback();
        break;
      default:
        _togglePlayback();
    }
  }

  Future<void> _openSettings() async {
    if (_showSettings || !mounted) return;
    _playerBackArmed = false;
    _hideControlsTimer?.cancel();
    setState(() {
      _showSettings = true;
      _showControls = true;
    });
    await showInstantDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var isClosing = false;
        var allowPop = false;
        bool? hasTracks;
        var trackAvailabilityRequested = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!trackAvailabilityRequested) {
              trackAvailabilityRequested = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                final available = await _playerEngine.hasSelectableTracks();
                if (dialogContext.mounted && !isClosing) {
                  setDialogState(() => hasTracks = available);
                }
              });
            }

            void closeDialog() {
              if (isClosing) return;
              isClosing = true;
              _blockPlayerBackUntilKeyRelease();
              setDialogState(() => allowPop = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              });
            }

            return PopScope(
              canPop: allowPop,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop) closeDialog();
              },
              child: SettingsOverlay(
                vodPlaybackSettings: true,
                playerEngine: _playerEngine,
                selectableTracksAvailable: hasTracks,
                onClose: closeDialog,
              ),
            );
          },
        );
      },
    );
    if (!mounted) return;
    _blockPlayerBackUntilKeyRelease();
    _settingsClosedAt = DateTime.now();
    setState(() => _showSettings = false);
    await _applyVodEnginePreference();
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_keyboardFocusNode);
    if (_isPlaying) _startHideControlsTimer();
  }

  void _blockPlayerBackUntilKeyRelease() {
    _blockBackUntilRelease = true;
    _backReleaseFallback?.cancel();
    _backReleaseFallback = Timer(const Duration(seconds: 2), () {
      _blockBackUntilRelease = false;
    });
  }

  void _releasePlayerBackBlock() {
    _blockBackUntilRelease = false;
    _backReleaseFallback?.cancel();
    _backReleaseFallback = null;
  }

  bool _isSeekBackwardKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.mediaRewind;

  bool _isSeekForwardKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.mediaFastForward;

  void _handleSeekPress(KeyEvent event, int direction) {
    if (event is KeyDownEvent) {
      _activeSeekKey = event.logicalKey;
      _seekRepeatCount = 0;
      _resumeAfterFastSeek = _isPlaying;
      if (_resumeAfterFastSeek) _playerEngine.pause();
    } else {
      _seekRepeatCount++;
    }

    if (_seekRepeatCount >= 3 && !_fastSeekMode) {
      _fastSeekMode = true;
      _scrubPreviewPosition = _playerEngine.position;
    }

    final seconds = _seekRepeatCount < 3
        ? 10
        : _seekRepeatCount < 8
            ? 30
            : 60;
    if (_fastSeekMode) {
      final duration = _playerEngine.duration;
      final current = _scrubPreviewPosition ?? _playerEngine.position;
      var target = current + Duration(seconds: seconds * direction);
      if (target < Duration.zero) target = Duration.zero;
      if (duration > Duration.zero && target > duration) target = duration;
      _scrubPreviewPosition = target;
    } else {
      _seekRelative(Duration(seconds: seconds * direction));
    }
    setState(() {
      _showControls = true;
      _uiFocused = true;
      _focusedControl = 'timeline';
    });
    if (_fastSeekMode) _hideControlsTimer?.cancel();
  }

  void _finishSeekHold() {
    final wasFastSeeking = _fastSeekMode;
    final target = _scrubPreviewPosition;
    final shouldResume = _resumeAfterFastSeek;
    setState(() {
      _activeSeekKey = null;
      _seekRepeatCount = 0;
    });
    if (wasFastSeeking && target != null) {
      _playerEngine.seek(target).whenComplete(() {
        if (shouldResume) _playerEngine.play();
        if (!mounted) return;
        setState(() {
          _fastSeekMode = false;
          _resumeAfterFastSeek = false;
          _scrubPreviewPosition = null;
        });
        _showControlsTemporarily();
      });
    } else {
      if (shouldResume) _playerEngine.play();
      setState(() {
        _fastSeekMode = false;
        _resumeAfterFastSeek = false;
        _scrubPreviewPosition = null;
      });
      _showControlsTemporarily();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showSettings || _blockBackUntilRelease || !_playerBackArmed) {
          return;
        } else if (_showControls) {
          setState(() {
            _showControls = false;
            _uiFocused = false;
            _playerBackArmed = false;
          });
        }
      },
      child: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) {
          return Focus(
            focusNode: _keyboardFocusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              final isBackKey = event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack;
              if (isBackKey && event is KeyUpEvent) {
                if (_blockBackUntilRelease) {
                  _releasePlayerBackBlock();
                  _playerBackArmed = true;
                  return KeyEventResult.handled;
                }
                if (!_playerBackArmed) {
                  _playerBackArmed = true;
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              }
              if (event is KeyUpEvent && _activeSeekKey == event.logicalKey) {
                _finishSeekHold();
                return KeyEventResult.handled;
              }
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              final key = event.logicalKey;

              if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.goBack) {
                if (_blockBackUntilRelease) {
                  return KeyEventResult.handled;
                }
                final justClosedSettings = _settingsClosedAt != null &&
                    DateTime.now().difference(_settingsClosedAt!) <
                        const Duration(milliseconds: 400);
                if (_showSettings || justClosedSettings) {
                  return KeyEventResult.handled;
                }
                if (_showControls) {
                  _hideControlsTimer?.cancel();
                  setState(() {
                    _showControls = false;
                    _uiFocused = false;
                    _playerBackArmed = false;
                  });
                  return KeyEventResult.handled;
                }
                if (!_playerBackArmed) {
                  return KeyEventResult.handled;
                }
                unawaited(_exitPlayer());
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.audioVolumeUp ||
                  key == LogicalKeyboardKey.numpadAdd ||
                  key == LogicalKeyboardKey.add ||
                  key == LogicalKeyboardKey.equal) {
                _adjustVolume(5.0);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.audioVolumeDown ||
                  key == LogicalKeyboardKey.numpadSubtract ||
                  key == LogicalKeyboardKey.minus) {
                _adjustVolume(-5.0);
                return KeyEventResult.handled;
              }
              if (event is KeyDownEvent &&
                  (key == LogicalKeyboardKey.audioVolumeMute ||
                      key == LogicalKeyboardKey.f8 ||
                      key == LogicalKeyboardKey.keyM)) {
                _toggleMute();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.space ||
                  key == LogicalKeyboardKey.mediaPlayPause ||
                  key == LogicalKeyboardKey.mediaPlay ||
                  key == LogicalKeyboardKey.mediaPause) {
                _togglePlayback();
                return KeyEventResult.handled;
              }

              final isBackward = _isSeekBackwardKey(key);
              final isForward = _isSeekForwardKey(key);
              final isDedicatedSeekKey =
                  key == LogicalKeyboardKey.mediaRewind ||
                      key == LogicalKeyboardKey.mediaFastForward;
              final isTimelineArrow =
                  _uiFocused && _focusedControl == 'timeline';
              if ((isBackward || isForward) &&
                  (isDedicatedSeekKey || isTimelineArrow || !_uiFocused)) {
                _handleSeekPress(event, isBackward ? -1 : 1);
                return KeyEventResult.handled;
              }

              // ==== YENİ KONTROL MANTIĞI ====
              // Mod 1: Normal Mod (sarma modu) - Sol/Sağ = ileri/geri, Yukarı = buton moduna geç
              // Mod 2: UI Focus Modu - Sol/Sağ = butonlar arası geçiş, Aşağı = sarma moduna dön

              if (_uiFocused) {
                // ---- UI FOCUS MODU ----
                if (_focusedControl == 'prev' || _focusedControl == 'next') {
                  if (_focusedControl == 'prev' &&
                      key == LogicalKeyboardKey.arrowRight) {
                    _focusBottomControl('rewind');
                    return KeyEventResult.handled;
                  }
                  if (_focusedControl == 'next' &&
                      key == LogicalKeyboardKey.arrowLeft) {
                    _focusBottomControl('forward');
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft && _hasPrev) {
                    _focusBottomControl('prev');
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowRight && _hasNext) {
                    _focusBottomControl('next');
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowDown) {
                    _focusBottomControl('play');
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.select ||
                      key == LogicalKeyboardKey.enter) {
                    if (_focusedControl == 'prev') {
                      _playPrevEpisode();
                    } else {
                      _playNextEpisode();
                    }
                    return KeyEventResult.handled;
                  }
                }
                if (key == LogicalKeyboardKey.arrowLeft) {
                  if (_focusedControl == 'rewind' && _hasPrev) {
                    _focusBottomControl('prev');
                    return KeyEventResult.handled;
                  }
                  _moveBottomControl(-1);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight) {
                  if (_focusedControl == 'forward' && _hasNext) {
                    _focusBottomControl('next');
                    return KeyEventResult.handled;
                  }
                  _moveBottomControl(1);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowDown) {
                  _focusBottomControl('timeline');
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowUp) {
                  if (_focusedControl == 'timeline') {
                    _focusBottomControl('play');
                  } else if (_focusedControl == 'prev' ||
                      _focusedControl == 'next') {
                    return KeyEventResult.handled;
                  } else if (widget.playlist != null &&
                      (_hasPrev || _hasNext)) {
                    _focusBottomControl(_hasPrev ? 'prev' : 'next');
                  } else {
                    _focusBottomControl('play');
                  }
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.enter) {
                  _activateFocusedControl();
                  return KeyEventResult.handled;
                }
              } else {
                // ---- NORMAL MOD (Sarma/İzleme Modu) ----
                if (key == LogicalKeyboardKey.arrowUp) {
                  _focusBottomControl('play');
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowDown) {
                  _focusBottomControl('play');
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.enter) {
                  if (!_showSettings) _togglePlayback();
                  return KeyEventResult.handled;
                }
              }

              return KeyEventResult.ignored;
            },
            child: Scaffold(
              backgroundColor: _videoSurfaceVisible &&
                      (_playerEngine.engineType == PlayerEngineType.exoPlayer ||
                          _playerEngine.engineType ==
                              PlayerEngineType.fireTvMedia3)
                  ? Colors.transparent
                  : Colors.black,
              body: MouseRegion(
                onHover: (_) => _showControlsTemporarily(),
                child: Stack(
                  children: [
                    // Layer 1: Player
                    GestureDetector(
                      onTap: _toggleControls,
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: RepaintBoundary(
                          child: AppVideoWidget(playerEngine: _playerEngine),
                        ),
                      ),
                    ),

                    // Layer 2: Brightness Overlay
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: Colors.black.withValues(
                            alpha: (1.0 - _brightness).clamp(0.0, 0.9),
                          ),
                        ),
                      ),
                    ),

                    // Layer 3: Controls (Üst bar + Merkez butonlar)
                    Positioned.fill(
                      child: AnimatedOpacity(
                        duration: Duration.zero,
                        opacity: _showControls ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: Stack(
                            children: [
                              if (!_fastSeekMode) _buildTopBar(),
                              if (!_fastSeekMode) _buildCenterControls(),
                              _buildBottomBar(),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Layer 4: Volume Indicator
                    if (_showVolumeIndicator) _buildVolumeIndicator(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCenterControls() {
    if (widget.playlist == null) return const SizedBox.shrink();

    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Önceki Bölüm
          if (_hasPrev)
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: _buildNavButton(
                icon: Icons.skip_previous,
                label: 'Önceki',
                isFocused: _uiFocused && _focusedControl == 'prev',
                onTap: _playPrevEpisode,
              ),
            )
          else
            const SizedBox(width: 100),

          // Oynat/duraklat alttaki ortak kontrol çubuğunda bulunur.
          const SizedBox(width: 100),

          // Sonraki Bölüm
          if (_hasNext)
            Padding(
              padding: const EdgeInsets.only(right: 48),
              child: _buildNavButton(
                icon: Icons.skip_next,
                label: 'Sonraki',
                isFocused: _uiFocused && _focusedControl == 'next',
                onTap: _playNextEpisode,
              ),
            )
          else
            const SizedBox(width: 100),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    required bool isFocused,
    required VoidCallback onTap,
    double size = 48,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration.zero,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: isFocused ? 0.8 : 0.4),
          shape: BoxShape.circle,
          border: Border.all(
            color: isFocused ? _settings.primaryColor : Colors.transparent,
            width: 3,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: _settings.primaryColor.withValues(alpha: 0.5),
                    blurRadius: 20,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, color: Colors.white, size: size)],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => unawaited(_exitPlayer()),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentTitle,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white, size: 28),
              onPressed: _openSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_fastSeekMode) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildBottomControl(
                    control: 'rewind',
                    icon: Icons.replay_10,
                    onPressed: () =>
                        _seekRelative(const Duration(seconds: -10)),
                  ),
                  const SizedBox(width: 12),
                  _buildBottomControl(
                    control: 'play',
                    icon: _isPlaying ? Icons.pause : Icons.play_arrow,
                    onPressed: _togglePlayback,
                    emphasized: true,
                  ),
                  const SizedBox(width: 12),
                  _buildBottomControl(
                    control: 'forward',
                    icon: Icons.forward_10,
                    onPressed: () => _seekRelative(const Duration(seconds: 10)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            AnimatedContainer(
              duration: Duration.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _uiFocused && _focusedControl == 'timeline'
                      ? _settings.primaryColor
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  StreamBuilder<Duration>(
                    stream: _playerEngine.positionStream,
                    builder: (context, snapshot) {
                      final pos = _scrubPreviewPosition ??
                          snapshot.data ??
                          Duration.zero;
                      return Text(
                        _formatDuration(pos),
                        style: GoogleFonts.splineSans(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StreamBuilder<Duration>(
                      stream: _playerEngine.positionStream,
                      builder: (context, snapshotPos) {
                        final visiblePosition =
                            _scrubPreviewPosition ?? snapshotPos.data;
                        final currentPos =
                            visiblePosition?.inMilliseconds.toDouble() ?? 0.0;
                        final duration =
                            _playerEngine.duration.inMilliseconds.toDouble();
                        final maxVal = duration > 0 ? duration : 1.0;
                        final val = currentPos.clamp(0.0, maxVal);

                        final timelineFocused =
                            _uiFocused && _focusedControl == 'timeline';
                        return SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: timelineFocused ? 9 : 6,
                              elevation: timelineFocused ? 6 : 1,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor: _settings.primaryColor,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: _settings.primaryColor,
                          ),
                          child: Slider(
                            value: val,
                            min: 0.0,
                            max: maxVal,
                            onChanged: (newVal) {
                              _playerEngine.seek(
                                Duration(milliseconds: newVal.toInt()),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  StreamBuilder<Duration>(
                    stream: _playerEngine.durationStream,
                    builder: (context, snapshot) {
                      final dur = snapshot.data ?? Duration.zero;
                      return Text(
                        _formatDuration(dur),
                        style: GoogleFonts.splineSans(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControl({
    required String control,
    required IconData icon,
    required VoidCallback onPressed,
    bool emphasized = false,
  }) {
    final isFocused = _uiFocused && _focusedControl == control;
    return AnimatedContainer(
      duration: Duration.zero,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isFocused ? _settings.primaryColor : Colors.transparent,
          width: 3,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: _settings.primaryColor.withValues(alpha: 0.45),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: IconButton(
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: emphasized
              ? _settings.primaryColor
              : Colors.white.withValues(alpha: 0.12),
          foregroundColor: Colors.white,
        ),
        icon: Icon(icon, size: emphasized ? 26 : 22),
      ),
    );
  }

  Widget _buildVolumeIndicator() {
    return Positioned(
      top: 40,
      right: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              _volume == 0
                  ? Icons.volume_off
                  : _volume < 50
                      ? Icons.volume_down
                      : Icons.volume_up,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: RotatedBox(
                quarterTurns: 3,
                child: LinearProgressIndicator(
                  value: _volume / 100,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _settings.primaryColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${_volume.toInt()}%',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
