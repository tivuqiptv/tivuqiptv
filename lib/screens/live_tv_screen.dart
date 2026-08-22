import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/player_engine.dart';
import '../services/epg_service.dart';
import '../services/local_companion_service.dart';
import '../utils/scoped_category.dart';
import '../player/playback_diagnostics.dart';
import '../widgets/app_video_widget.dart';
import '../widgets/diagnostics_overlay_widget.dart';
import '../widgets/settings_overlay.dart';
import '../utils/instant_dialog.dart';
import '../providers/settings_provider.dart';
import '../models/profile.dart';
import '../providers/channel_provider.dart';
import '../models/channel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/top_nav_bar.dart';
import '../utils/remote_long_press.dart';
import '../utils/parental_category_access.dart';
import 'user_selection_screen.dart';

enum _RemoteMode {
  watching,
  sidebarHeader,
  sidebarChannels,
  sidebarCategories,
  sidebarProfiles,
  sidebarFooter,
  recentChannels,
  topNav
}

class LiveTVScreen extends StatefulWidget {
  const LiveTVScreen({super.key, this.initialRemoteChannelId});

  final String? initialRemoteChannelId;
  @override
  State<LiveTVScreen> createState() => _LiveTVScreenState();
}

class _LiveTVScreenState extends State<LiveTVScreen>
    with WidgetsBindingObserver {
  Channel? _playingChannel;
  AppPlayerEngine _playerEngine = AppPlayerEngine();
  PlaybackDiagnostics _diagnostics = const PlaybackDiagnostics();
  bool _isPlaying = false;
  bool _resumePlaybackAfterLifecyclePause = false;
  bool _resumeAfterPhoneContent = false;
  LocalChannelPlayRequest? _pendingPhoneChannelRequest;
  String? _pendingInitialRemoteChannelId;
  bool _isBuffering =
      false; // Gerçek buffering durumu — 1.5s debounce ile güncellenir
  bool _isActuallyBuffering = false; // MPV'den gelen ham sinyal
  String? _playbackError;
  String? _currentProgramTitle;
  final EpgService _epgService = EpgService();
  Timer? _epgRefreshTimer;
  int _epgGeneration = 0;
  int _playbackGeneration = 0;
  Timer? _bufferingDebounceTimer;
  Timer? _streamRecoveryTimer;
  Timer? _streamRecoveryResetTimer;
  int _streamRecoveryAttempts = 0;
  bool _isRecoveringStream = false;
  bool _streamReadyForRecovery = false;
  Future<void>? _liveDisplayPreparation;

  StreamSubscription? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription? _diagSub;
  StreamSubscription? _bufferSub;
  Duration _lastPlaybackPosition = Duration.zero;
  DateTime _lastPlaybackProgressAt = DateTime.now();

  bool _showControls = true;
  bool _isMouseInSidebar = false;
  bool _isMouseInControls = false;
  String _searchQuery = '';
  String _selectedCategory = 'Tümü';
  final _settings = SettingsProvider();

  Timer? _hideControlsTimer;
  Timer? _hideSidebarTimer;

  List<String> _categories = ['Tümü', 'Favoriler'];
  List<Channel> _filteredChannels = [];
  Map<String, int> _liveCategoryCounts = const {};

  double _volume = 80.0;
  final double _brightness = 1.0;
  double _lastNonZeroVolume = 80.0;

  bool _showVolumeIndicator = false;
  Timer? _volumeIndicatorTimer;

  final ScrollController _scrollController = ScrollController();
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _categorySidebarScrollController = ScrollController();
  final ScrollController _profileSidebarScrollController = ScrollController();
  final ScrollController _recentChannelsScrollController = ScrollController();
  final Map<String, GlobalKey> _categoryKeys = {};
  final Map<String, GlobalKey> _categorySidebarKeys = {};
  final GlobalKey<TopNavBarState> _topNavKey = GlobalKey<TopNavBarState>();
  ChannelProvider? _channelProvider;

  int _focusedCategoryIndex = 0;
  int _focusedProfileIndex = 0;
  int _focusedChannelIndex = -1;
  int _focusedHeaderIndex = 0;
  int _focusedRecentChannelIndex = 0;
  List<String> _recentLiveChannelUrls = <String>[];
  Future<void>? _recentChannelsLoad;

  _RemoteMode _remoteMode = _RemoteMode.watching;
  String? _selectedProfileId;
  DateTime? _topNavOpenedAt;
  DateTime? _lastModalClosedAt;
  final RemoteLongPress _favoriteLongPress = RemoteLongPress();
  final RemoteLongPress _categoryLongPress = RemoteLongPress();
  bool _closeAfterCategoryChannelSelection = false;
  bool get _showSidebar =>
      _remoteMode == _RemoteMode.sidebarHeader ||
      _remoteMode == _RemoteMode.sidebarChannels ||
      _remoteMode == _RemoteMode.sidebarCategories ||
      _remoteMode == _RemoteMode.sidebarProfiles ||
      _remoteMode == _RemoteMode.sidebarFooter;
  bool get _showCategoriesSidebar =>
      _remoteMode == _RemoteMode.sidebarCategories;
  bool get _showProfilesSidebar => _remoteMode == _RemoteMode.sidebarProfiles;
  bool get _hasMultipleProfiles => _settings.profiles.length > 1;
  bool get _showRecentChannels => _remoteMode == _RemoteMode.recentChannels;

  static const double _itemH = 42.0;
  // Leave enough vertical paint space for the 2 px focus border and bold text.
  static const double _categoryItemH = 50.0;

  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  String _channelNumberInput = '';
  Timer? _channelNumberTimer;

  // Scroll to center the focused channel index
  void _scrollToFocused() {
    if (_filteredChannels.isEmpty) return;
    if (!_scrollController.hasClients) return;
    final double viewport = _scrollController.position.viewportDimension;
    final double maxScroll = _scrollController.position.maxScrollExtent;
    final double itemCenter = _focusedChannelIndex * _itemH + (_itemH / 2.0);
    final double targetOffset = itemCenter - (viewport / 2.0);
    _scrollController.jumpTo(targetOffset.clamp(0.0, maxScroll));
  }

  String _getCategoryKey(String cat) {
    switch (cat) {
      case 'Tümü':
        return 'all';
      case 'Favoriler':
        return 'favorites_cat';
      default:
        return cat;
    }
  }

  void _subscribeToPlayerStreams() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _diagSub?.cancel();
    _bufferSub?.cancel();

    _playingSub = _playerEngine.isPlayingStream.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _positionSub = _playerEngine.positionStream.listen((position) {
      if (position >
          _lastPlaybackPosition + const Duration(milliseconds: 200)) {
        _lastPlaybackProgressAt = DateTime.now();
      }
      _lastPlaybackPosition = position;
    });
    if (_settings.showDiagnostics) {
      _diagSub = _playerEngine.diagnosticsStream.listen((diag) {
        if (mounted) setState(() => _diagnostics = diag);
      });
    }
    _bufferSub = _playerEngine.isBufferingStream.listen((buffering) {
      if (!mounted) return;
      _isActuallyBuffering = buffering;
      if (!buffering) {
        _bufferingDebounceTimer?.cancel();
        _streamRecoveryTimer?.cancel();
        _streamRecoveryResetTimer?.cancel();
        _streamRecoveryResetTimer = Timer(const Duration(seconds: 20), () {
          _streamRecoveryAttempts = 0;
        });
        if (mounted) setState(() => _isBuffering = false);
      } else {
        _bufferingDebounceTimer?.cancel();
        _bufferingDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
          final playbackHasStopped =
              DateTime.now().difference(_lastPlaybackProgressAt) >=
                  const Duration(seconds: 2);
          if (mounted && _isActuallyBuffering && playbackHasStopped) {
            setState(() => _isBuffering = true);
          }
        });
        _scheduleStreamRecovery();
      }
    });
  }

  void _scheduleStreamRecovery() {
    if (!_streamReadyForRecovery ||
        _isRecoveringStream ||
        _streamRecoveryAttempts >= 2) {
      return;
    }
    _streamRecoveryTimer?.cancel();
    final generation = _playbackGeneration;
    final channelUrl = _playingChannel?.url;
    _streamRecoveryTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted ||
          !_isActuallyBuffering ||
          generation != _playbackGeneration ||
          channelUrl == null ||
          channelUrl != _playingChannel?.url) {
        return;
      }
      // Some providers briefly report BUFFERING while decoded frames are still
      // advancing. Reopening the player in that state causes visible flicker.
      if (DateTime.now().difference(_lastPlaybackProgressAt) <
          const Duration(seconds: 8)) {
        _scheduleStreamRecovery();
        return;
      }
      unawaited(_recoverStalledStream(generation, channelUrl));
    });
  }

  Future<void> _recoverStalledStream(int generation, String channelUrl) async {
    if (_isRecoveringStream || _streamRecoveryAttempts >= 2) return;
    _isRecoveringStream = true;
    _streamRecoveryAttempts++;
    final switchEngine = _streamRecoveryAttempts == 2;
    try {
      await _playerEngine
          .recoverLastPlayback(switchNativeEngine: switchEngine)
          .timeout(const Duration(seconds: 22));
    } catch (error) {
      debugPrint(
        'Yayın kurtarma $_streamRecoveryAttempts. denemede tamamlanamadı: '
        '${error.runtimeType}',
      );
    } finally {
      _isRecoveringStream = false;
    }
    if (!mounted ||
        generation != _playbackGeneration ||
        channelUrl != _playingChannel?.url) {
      return;
    }
    if (_isActuallyBuffering) _scheduleStreamRecovery();
  }

  void _resetStreamRecoveryForChannelChange() {
    _streamRecoveryTimer?.cancel();
    _streamRecoveryResetTimer?.cancel();
    _streamRecoveryAttempts = 0;
    _isRecoveringStream = false;
    _streamReadyForRecovery = false;
    _lastPlaybackPosition = Duration.zero;
    _lastPlaybackProgressAt = DateTime.now();
  }

  @override
  void initState() {
    super.initState();
    _pendingInitialRemoteChannelId = widget.initialRemoteChannelId;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleGlobalHardwareKey);
    LocalCompanionService.channelPlayRequest.addListener(
      _handlePhoneChannelPlayRequest,
    );
    LocalCompanionService.contentPlayRequest.addListener(
      _handlePhoneContentPlayRequest,
    );
    LocalCompanionService.contentPlaybackClosed.addListener(
      _handlePhoneContentClosed,
    );
    LocalCompanionService.vodPlaybackDepth.addListener(
      _handleVodPlaybackDepthChanged,
    );
    _settings.setLastState(screen: 'live_tv');
    _recentChannelsLoad = _loadRecentChannels();
    unawaited(_recentChannelsLoad);
    _subscribeToPlayerStreams();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = Provider.of<ChannelProvider>(context, listen: false);
      _channelProvider = provider;
      provider.addListener(_handleCatalogChanged);
      _updateCategories(provider.liveChannels);
      final visibleChannels = provider.liveChannels
          .where((channel) => !_settings.isCategoryHidden(
                'live',
                categoryLabel(channel.category),
                profileId: channel.sourceProfileId,
              ))
          .toList(growable: false);
      if (visibleChannels.isNotEmpty) {
        Channel initialChannel = visibleChannels[0];
        final requestedId = _pendingInitialRemoteChannelId;
        if (requestedId != null) {
          final requested = visibleChannels.where(
            (channel) => channelRemoteId(channel) == requestedId,
          );
          if (requested.isNotEmpty) {
            initialChannel = requested.first;
            _pendingInitialRemoteChannelId = null;
          }
        } else if (_settings.lastWatchedChannelUrl != null) {
          try {
            initialChannel = visibleChannels.firstWhere(
              (c) => c.url == _settings.lastWatchedChannelUrl,
            );
          } catch (_) {}
        }
        setState(() {
          _selectedCategory = initialChannel.category;
          _playingChannel = initialChannel;
        });
      } else if (_settings.lastWatchedChannelUrl?.isNotEmpty == true) {
        // Start the persisted stream immediately. The full cached catalogue is
        // attached later without restarting a healthy player.
        setState(() {
          _selectedCategory = 'Tümü';
          _playingChannel = Channel(
            id: 'last-watched-bootstrap',
            name: _settings.getText('live_tv'),
            url: _settings.lastWatchedChannelUrl!,
          );
        });
      }
      _filterChannels();
      await _ensureLiveDisplayModePrepared();
      if (!mounted) return;
      await _initializePlayer();
      await Future.delayed(const Duration(milliseconds: 600));
      _scrollToSelected();
      _scrollToSelectedHorizontalCategory();
    });
    _startHideSidebarTimer();
  }

  void _handleCatalogChanged() {
    if (!mounted || _channelProvider == null) return;
    final channels = _channelProvider!.liveChannels;
    _updateCategories(channels);

    final requestedId = _pendingInitialRemoteChannelId;
    if (requestedId != null) {
      final requested = channels.where(
        (channel) =>
            channelRemoteId(channel) == requestedId &&
            !_settings.isCategoryHidden(
              'live',
              categoryLabel(channel.category),
              profileId: channel.sourceProfileId,
            ),
      );
      if (requested.isNotEmpty) {
        final selected = requested.first;
        _pendingInitialRemoteChannelId = null;
        setState(() {
          _playingChannel = selected;
          _selectedCategory = selected.category;
        });
        _filterChannels();
        _settings.setLastWatchedChannelUrl(selected.url);
        unawaited(_initializePlayer());
        return;
      }
    }

    final currentUrl = _playingChannel?.url;
    Channel? resolved;
    if (currentUrl != null) {
      for (final channel in channels) {
        if (channel.url == currentUrl) {
          resolved = channel;
          break;
        }
      }
    }

    if (resolved != null) {
      final wasBootstrap = _playingChannel?.id == 'last-watched-bootstrap';
      setState(() {
        _playingChannel = resolved;
        _selectedCategory = resolved!.category;
      });
      _filterChannels();
      if (wasBootstrap && _playbackError != null) {
        unawaited(_initializePlayer());
      }
      return;
    }

    if (_playingChannel == null && channels.isNotEmpty) {
      final first = channels.first;
      setState(() {
        _playingChannel = first;
        _selectedCategory = first.category;
      });
      _filterChannels();
      _settings.setLastWatchedChannelUrl(first.url);
      unawaited(_initializePlayer());
      return;
    }
    _filterChannels();
  }

  void _handlePhoneChannelPlayRequest() {
    final request = LocalCompanionService.channelPlayRequest.value;
    if (request == null || !mounted) return;
    if (LocalCompanionService.vodPlaybackDepth.value > 0) {
      _pendingPhoneChannelRequest = request;
      return;
    }
    _playPhoneChannelRequest(request);
  }

  void _handleVodPlaybackDepthChanged() {
    if (!mounted || LocalCompanionService.vodPlaybackDepth.value > 0) return;
    final pending = _pendingPhoneChannelRequest;
    if (pending == null) return;
    _pendingPhoneChannelRequest = null;
    _playPhoneChannelRequest(pending);
  }

  void _playPhoneChannelRequest(LocalChannelPlayRequest request) {
    final channels = Provider.of<ChannelProvider>(
      context,
      listen: false,
    ).liveChannels;
    final matches = channels.where(
      (channel) => channelRemoteId(channel) == request.id,
    );
    if (matches.isEmpty) return;
    final selected = matches.first;
    if (_settings.isCategoryHidden(
      'live',
      categoryLabel(selected.category),
      profileId: selected.sourceProfileId,
    )) {
      return;
    }

    _hideSidebarTimer?.cancel();
    _hideControlsTimer?.cancel();
    _resumeAfterPhoneContent = false;
    setState(() {
      _selectedCategory = selected.category;
      _playingChannel = selected;
      _remoteMode = _RemoteMode.watching;
      _showControls = false;
    });
    _filterChannels();
    _settings.setLastWatchedChannelUrl(selected.url);
    unawaited(_initializePlayer());
    FocusScope.of(context).requestFocus(_keyboardFocusNode);
  }

  void _handlePhoneContentPlayRequest() {
    if (!mounted) return;
    _resumeAfterPhoneContent = _isPlaying;
    unawaited(_playerEngine.pause());
  }

  void _handlePhoneContentClosed() {
    if (!mounted || !_resumeAfterPhoneContent) return;
    _resumeAfterPhoneContent = false;
    unawaited(_playerEngine.play());
  }

  void _updateCategories(List<Channel> channels) {
    if (_selectedProfileId != null &&
        !_settings.profiles
            .any((profile) => profile.id == _selectedProfileId)) {
      _selectedProfileId = null;
    }
    final profileChannels = channels
        .where((channel) => _matchesSelectedProfile(channel))
        .toList(growable: false);
    setState(() {
      final channelCats = profileChannels
          .map((c) => c.category)
          .where((cat) =>
              cat != 'Tümü' &&
              cat != 'Favoriler' &&
              !_settings.isCategoryHidden(
                'live',
                categoryLabel(cat),
                profileId: categoryProfileId(cat),
              ))
          .toSet()
          .toList();
      _categories = ['Tümü', 'Favoriler', ...channelCats];
      _liveCategoryCounts = _buildLiveCategoryCounts(profileChannels);
      if (!_categories.contains(_selectedCategory)) {
        _selectedCategory = 'Tümü';
      }
      for (var cat in _categories) {
        _categoryKeys.putIfAbsent(cat, () => GlobalKey());
        _categorySidebarKeys.putIfAbsent(cat, () => GlobalKey());
      }
    });
  }

  bool _matchesSelectedProfile(Channel channel) =>
      _selectedProfileId == null ||
      channel.sourceProfileId == _selectedProfileId;

  int _profileChannelCount(String? profileId) {
    final channels = Provider.of<ChannelProvider>(
      context,
      listen: false,
    ).liveChannels;
    return channels.where((channel) {
      if (profileId != null && channel.sourceProfileId != profileId) {
        return false;
      }
      return !_settings.isCategoryHidden(
        'live',
        categoryLabel(channel.category),
        profileId: channel.sourceProfileId,
      );
    }).length;
  }

  Map<String, int> _buildLiveCategoryCounts(List<Channel> channels) {
    channels = channels
        .where(
          (channel) =>
              _matchesSelectedProfile(channel) &&
              !_settings.isCategoryHidden(
                'live',
                categoryLabel(channel.category),
                profileId: channel.sourceProfileId,
              ),
        )
        .toList(growable: false);
    final counts = <String, int>{'Tümü': channels.length, 'Favoriler': 0};
    for (final channel in channels) {
      counts[channel.category] = (counts[channel.category] ?? 0) + 1;
      if (_settings.isFavorite(
        'live',
        channel.url,
        profileId: channel.sourceProfileId,
      )) {
        counts['Favoriler'] = (counts['Favoriler'] ?? 0) + 1;
      }
    }
    return counts;
  }

  void _refreshLiveCategoryCounts() {
    final channels =
        Provider.of<ChannelProvider>(context, listen: false).liveChannels;
    setState(() => _liveCategoryCounts = _buildLiveCategoryCounts(channels));
  }

  Future<void> _initializePlayer() async {
    await _waitForPhoneVodToClose();
    if (!mounted) return;
    // Every entry point (catalog refresh, companion request and remote channel
    // change included) must wait for the selected live-TV display mode. This
    // keeps ExoPlayer's release clock from being created while Fire TV still
    // reports the previous 60 Hz mode.
    await _ensureLiveDisplayModePrepared();
    if (!mounted) return;
    LocalCompanionService.liveTvTransitionInProgress = false;
    if (_playingChannel == null) return;
    _resetStreamRecoveryForChannelChange();
    final generation = ++_playbackGeneration;
    var channelToOpen = _playingChannel!;
    final latestChannels =
        Provider.of<ChannelProvider>(context, listen: false).liveChannels;
    final latestIndex = latestChannels
        .indexWhere((channel) => channel.url == channelToOpen.url);
    if (latestIndex >= 0) {
      channelToOpen = latestChannels[latestIndex];
      _playingChannel = channelToOpen;
    }
    unawaited(_loadCurrentProgram(channelToOpen));
    final url = channelToOpen.url;
    if (url.isEmpty) return;
    try {
      if (mounted) {
        setState(() {
          _playbackError = null;
          _isBuffering = true;
        });
      }

      final targetEngineType =
          SettingsProvider().preferredEngine == 'fireTvMedia3'
              ? PlayerEngineType.fireTvMedia3
              : PlayerEngineType.exoPlayer;

      if (!_playerEngine.usesEngine(targetEngineType)) {
        await _playerEngine.dispose();
        if (!mounted) return;
        setState(() {
          _playerEngine = AppPlayerEngine(forceEngine: targetEngineType);
        });
        _subscribeToPlayerStreams();
      }

      await _playerEngine
          .openUrl(
            url,
            volume: _volume,
            enableTunneling: false,
            quality: _settings.quality,
            httpHeaders: channelToOpen.httpHeaders,
          )
          .timeout(const Duration(seconds: 22));
      if (generation != _playbackGeneration) return;
      _streamReadyForRecovery = true;
      unawaited(_recordSuccessfulChannel(channelToOpen.url));
      _startHideControlsTimer();
      _scrollToSelectedHorizontalCategory();
    } catch (e) {
      debugPrint('Error initializing video: $e');
      if (!mounted || generation != _playbackGeneration) return;
      _bufferingDebounceTimer?.cancel();
      _isActuallyBuffering = false;
      try {
        await _playerEngine.stop();
      } catch (_) {}
      if (!mounted || generation != _playbackGeneration) return;
      setState(() {
        _isBuffering = false;
        _playbackError = _settings.getText('stream_unavailable');
      });
    }
  }

  Future<void> _waitForPhoneVodToClose() async {
    if (LocalCompanionService.vodPlaybackDepth.value == 0) return;
    final completer = Completer<void>();
    void handleDepthChanged() {
      if (LocalCompanionService.vodPlaybackDepth.value == 0 &&
          !completer.isCompleted) {
        completer.complete();
      }
    }

    LocalCompanionService.vodPlaybackDepth.addListener(handleDepthChanged);
    try {
      await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      debugPrint(
          'VOD kapanışı beklenirken canlı TV geçişi zaman aşımına uğradı.');
    } finally {
      LocalCompanionService.vodPlaybackDepth.removeListener(handleDepthChanged);
    }
  }

  Future<void> _loadCurrentProgram(Channel channel) async {
    final generation = ++_epgGeneration;
    _epgRefreshTimer?.cancel();
    if (mounted) setState(() => _currentProgramTitle = null);
    final provider = Provider.of<ChannelProvider>(context, listen: false);
    final program = await _epgService.currentProgram(
      playlistUrl: provider.activePlaylistUrl,
      channel: channel,
    );
    if (!mounted ||
        generation != _epgGeneration ||
        channel.url != _playingChannel?.url) {
      return;
    }
    setState(() => _currentProgramTitle = program?.title);
    final now = DateTime.now();
    final untilEnd = program?.endsAt?.difference(now);
    final refreshAfter = untilEnd != null && untilEnd > Duration.zero
        ? untilEnd + const Duration(seconds: 2)
        : const Duration(minutes: 3);
    _epgRefreshTimer = Timer(refreshAfter, () {
      if (mounted && channel.url == _playingChannel?.url) {
        unawaited(_loadCurrentProgram(channel));
      }
    });
  }

  Future<void> _ensureLiveDisplayModePrepared() {
    return _liveDisplayPreparation ??=
        AppPlayerEngine.prepareLiveDisplayModeAndWait(
      refreshRate: _settings.liveTvRefreshRate,
    );
  }

  void _changeChannel(int index) {
    if (index < 0 || index >= _filteredChannels.length) return;
    setState(() {
      _playingChannel = _filteredChannels[index];
    });
    _settings.setLastWatchedChannelUrl(_playingChannel!.url);
    _initializePlayer();
    _scrollToSelected();
    _scrollToSelectedHorizontalCategory();
    FocusScope.of(context).requestFocus(_keyboardFocusNode);
    if (_closeAfterCategoryChannelSelection) {
      _closeAfterCategoryChannelSelection = false;
      _resetSidebarTimer();
    } else if (_remoteMode == _RemoteMode.sidebarChannels) {
      _resetSidebarTimer();
    }
  }

  void _changeChannelRelative(int delta) {
    if (_playingChannel == null) return;
    final playing = _playingChannel!;
    final allChannels =
        Provider.of<ChannelProvider>(context, listen: false).liveChannels;
    final activeCategoryChannels = allChannels
        .where((channel) =>
            channel.category == playing.category &&
            !_settings.isCategoryHidden(
              'live',
              categoryLabel(channel.category),
              profileId: channel.sourceProfileId,
            ))
        .toList(growable: false);
    if (activeCategoryChannels.isEmpty) return;
    int currentIdx =
        activeCategoryChannels.indexWhere((c) => c.url == playing.url);
    if (currentIdx == -1) currentIdx = 0;
    int nextIdx = currentIdx + delta;
    if (nextIdx < 0) nextIdx = activeCategoryChannels.length - 1;
    if (nextIdx >= activeCategoryChannels.length) nextIdx = 0;
    setState(() {
      _playingChannel = activeCategoryChannels[nextIdx];
    });
    _settings.setLastWatchedChannelUrl(_playingChannel!.url);
    _initializePlayer();
    setState(() => _showControls = true);
    _startHideControlsTimer();
    FocusScope.of(context).requestFocus(_keyboardFocusNode);
  }

  void _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;

    final bool isNavKey = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    if (event is KeyRepeatEvent && !isNavKey) {
      return; // Ignore repeat for OK, Back, Digits, etc.
    }

    // Settings only on KeyDown
    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.contextMenu ||
          key == LogicalKeyboardKey.f1) {
        _showSettings(context);
        return;
      }
    }

    switch (_remoteMode) {
      case _RemoteMode.watching:
        _handleWatching(key);
      case _RemoteMode.sidebarHeader:
        _handleSidebarHeader(key);
      case _RemoteMode.sidebarChannels:
        _handleSidebarChannels(key);
      case _RemoteMode.sidebarCategories:
        _handleSidebarCategories(key);
      case _RemoteMode.sidebarProfiles:
        _handleSidebarProfiles(key);
      case _RemoteMode.sidebarFooter:
        _handleSidebarFooter(key);
      case _RemoteMode.recentChannels:
        _handleRecentChannels(key);
      case _RemoteMode.topNav:
        _handleTopNav(key);
    }
  }

  void _handleWatching(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) {
      _changeChannelRelative(1);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _changeChannelRelative(-1);
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _switchToPreviousChannel();
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _openRecentChannels();
      return;
    }

    final digit = _digitFromKey(key);
    if (digit != null) {
      _handleDirectChannelInput(digit);
      return;
    }

    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      if (_channelNumberInput.isNotEmpty) {
        _submitChannelNumber();
      } else {
        _openSidebar();
      }
      return;
    }

    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      _openTopNav();
      return;
    }
  }

  String get _recentChannelsStorageKey =>
      'recentLiveChannelUrls_${_settings.lastProfileId ?? 'default'}';

  Future<void> _loadRecentChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final urls = prefs.getStringList(_recentChannelsStorageKey) ?? <String>[];
    if (!mounted) return;
    _recentLiveChannelUrls = urls.take(8).toList(growable: true);
  }

  Future<void> _recordSuccessfulChannel(String url) async {
    if (url.isEmpty) return;
    await _recentChannelsLoad;
    if (!mounted) return;
    _recentLiveChannelUrls
      ..remove(url)
      ..insert(0, url);
    if (_recentLiveChannelUrls.length > 8) {
      _recentLiveChannelUrls.removeRange(8, _recentLiveChannelUrls.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _recentChannelsStorageKey,
      List<String>.from(_recentLiveChannelUrls),
    );
    LocalCompanionService.liveRecentChannelsRevision.value++;
  }

  List<Channel> _resolvedRecentChannels() {
    final channels =
        Provider.of<ChannelProvider>(context, listen: false).liveChannels;
    final byUrl = <String, Channel>{
      for (final channel in channels) channel.url: channel
    };
    return _recentLiveChannelUrls
        .map((url) => byUrl[url])
        .whereType<Channel>()
        .take(8)
        .toList(growable: false);
  }

  void _playRecentChannel(Channel channel) {
    setState(() {
      _selectedCategory = channel.category;
      _playingChannel = channel;
      _remoteMode = _RemoteMode.watching;
      _showControls = true;
    });
    _filterChannels();
    _settings.setLastWatchedChannelUrl(channel.url);
    _initializePlayer();
    _startHideControlsTimer();
    _scrollToSelectedHorizontalCategory();
    FocusScope.of(context).requestFocus(_keyboardFocusNode);
  }

  void _switchToPreviousChannel() {
    for (final channel in _resolvedRecentChannels()) {
      if (channel.url != _playingChannel?.url) {
        _playRecentChannel(channel);
        return;
      }
    }
  }

  void _openRecentChannels() {
    final recent = _resolvedRecentChannels();
    final currentIndex =
        recent.indexWhere((channel) => channel.url == _playingChannel?.url);
    setState(() {
      _focusedRecentChannelIndex = currentIndex >= 0 ? currentIndex : 0;
      _remoteMode = _RemoteMode.recentChannels;
    });
    _scrollRecentChannelToFocused();
    _resetSidebarTimer();
  }

  void _handleRecentChannels(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      _hideSidebarTimer?.cancel();
      setState(() => _remoteMode = _RemoteMode.watching);
      return;
    }

    _resetSidebarTimer();
    final recent = _resolvedRecentChannels();
    if (recent.isEmpty) return;
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _focusedRecentChannelIndex =
            (_focusedRecentChannelIndex - 1 + recent.length) % recent.length;
      });
      _scrollRecentChannelToFocused();
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _focusedRecentChannelIndex =
            (_focusedRecentChannelIndex + 1) % recent.length;
      });
      _scrollRecentChannelToFocused();
      return;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      final index = _focusedRecentChannelIndex.clamp(0, recent.length - 1);
      _playRecentChannel(recent[index]);
    }
  }

  void _scrollRecentChannelToFocused() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_recentChannelsScrollController.hasClients) return;
      const itemHeight = 48.0;
      final position = _recentChannelsScrollController.position;
      final target = _focusedRecentChannelIndex * itemHeight -
          (position.viewportDimension - itemHeight) / 2;
      _recentChannelsScrollController
          .jumpTo(target.clamp(0.0, position.maxScrollExtent));
    });
  }

  void _handleSidebarChannels(LogicalKeyboardKey key) {
    // The sidebar timeout is an inactivity timeout. Every remote action while
    // the list is open starts a fresh full interval; Back still closes it
    // immediately through _closeSidebar below.
    _resetSidebarTimer();
    final digit = _digitFromKey(key);
    if (digit != null) {
      _handleDirectChannelInput(digit);
      return;
    }

    if (key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.pageDown) {
      _switchCategoryRelative(1);
      return;
    }
    if (key == LogicalKeyboardKey.mediaRewind ||
        key == LogicalKeyboardKey.pageUp) {
      _switchCategoryRelative(-1);
      return;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        if (_focusedChannelIndex < _filteredChannels.length - 1) {
          _focusedChannelIndex++;
          _scrollToFocused();
        } else {
          _remoteMode = _RemoteMode.sidebarFooter;
        }
      });
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_focusedChannelIndex > 0) {
          _focusedChannelIndex--;
          _scrollToFocused();
        } else {
          _remoteMode = _RemoteMode.sidebarHeader;
          _focusedHeaderIndex = 0;
        }
      });
      return;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      if (_channelNumberInput.isNotEmpty) {
        _submitChannelNumber();
      } else if (_focusedChannelIndex >= 0 &&
          _focusedChannelIndex < _filteredChannels.length) {
        _changeChannel(_focusedChannelIndex);
        _resetSidebarTimer();
      }
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        _remoteMode = _RemoteMode.sidebarCategories;
        _focusedCategoryIndex = _categories.indexOf(_selectedCategory);
        if (_focusedCategoryIndex < 0) _focusedCategoryIndex = 0;
      });
      _scrollToSelectedCategoryInSidebar();
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _closeSidebar();
      return;
    }
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      _closeSidebar();
      return;
    }
  }

  void _switchCategoryRelative(int delta) {
    if (_categories.isEmpty) return;
    int currentIdx = _categories.indexOf(_selectedCategory);
    if (currentIdx == -1) currentIdx = 0;
    int nextIdx = currentIdx + delta;
    if (nextIdx < 0) nextIdx = _categories.length - 1;
    if (nextIdx >= _categories.length) nextIdx = 0;

    setState(() {
      _selectedCategory = _categories[nextIdx];
      _searchQuery = ''; // Arama kutusunu temizle
      _focusedChannelIndex = 0;
    });
    _filterChannels();
    _scrollToFocused();
    _scrollToSelectedHorizontalCategory();
    _resetSidebarTimer();
  }

  void _toggleFocusedChannelFavorite() {
    if (_focusedChannelIndex < 0 ||
        _focusedChannelIndex >= _filteredChannels.length) {
      return;
    }
    final channel = _filteredChannels[_focusedChannelIndex];
    unawaited(
      _settings.toggleFavorite(
        'live',
        channel.url,
        profileId: channel.sourceProfileId,
      ),
    );
    _refreshLiveCategoryCounts();
    if (_selectedCategory == 'Favoriler') _filterChannels();
    // Uzun basış süresini liste kapanma süresinden düşme. Favori işlemi
    // tamamlandığı anda kullanıcıya tam bir görünürlük süresi ver.
    _resetSidebarTimer();
  }

  int _liveCategoryCount(String category) {
    return _liveCategoryCounts[category] ?? 0;
  }

  void _handleSidebarCategories(LogicalKeyboardKey key) {
    _resetSidebarTimer();
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_focusedCategoryIndex > 0) _focusedCategoryIndex--;
      });
      _scrollToCategoryIndex(_focusedCategoryIndex);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        if (_focusedCategoryIndex < _categories.length - 1) {
          _focusedCategoryIndex++;
        }
      });
      _scrollToCategoryIndex(_focusedCategoryIndex);
      return;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.arrowRight) {
      unawaited(_activateFocusedLiveCategory());
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!_hasMultipleProfiles) return;
      final profiles = _profileFilters;
      setState(() {
        _remoteMode = _RemoteMode.sidebarProfiles;
        _focusedProfileIndex = profiles.indexWhere(
          (profile) => profile?.id == _selectedProfileId,
        );
        if (_focusedProfileIndex < 0) _focusedProfileIndex = 0;
      });
      _scrollToProfileIndex(_focusedProfileIndex);
      return;
    }
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      _closeSidebar();
      return;
    }
  }

  List<Profile?> get _profileFilters => <Profile?>[
        null,
        ..._settings.profiles,
      ];

  void _handleSidebarProfiles(LogicalKeyboardKey key) {
    _resetSidebarTimer();
    final profiles = _profileFilters;
    if (profiles.isEmpty) return;
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_focusedProfileIndex > 0) _focusedProfileIndex--;
      });
      _scrollToProfileIndex(_focusedProfileIndex);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        if (_focusedProfileIndex < profiles.length - 1) {
          _focusedProfileIndex++;
        }
      });
      _scrollToProfileIndex(_focusedProfileIndex);
      return;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.arrowRight) {
      _activateFocusedProfile();
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft) return;
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      _closeSidebar();
    }
  }

  void _activateFocusedProfile() {
    final profiles = _profileFilters;
    if (_focusedProfileIndex < 0 || _focusedProfileIndex >= profiles.length) {
      return;
    }
    _selectedProfileId = profiles[_focusedProfileIndex]?.id;
    _selectedCategory = 'Tümü';
    _searchQuery = '';
    _searchController.clear();
    final channels = Provider.of<ChannelProvider>(
      context,
      listen: false,
    ).liveChannels;
    _updateCategories(channels);
    setState(() {
      _remoteMode = _RemoteMode.sidebarCategories;
      _focusedCategoryIndex = 0;
    });
    _filterChannels();
    _scrollToCategoryIndex(0);
    _resetSidebarTimer();
  }

  bool _isLockableLiveCategory(String category) =>
      category != 'Tümü' && category != 'Favoriler';

  Future<void> _activateFocusedLiveCategory() async {
    if (_focusedCategoryIndex < 0 ||
        _focusedCategoryIndex >= _categories.length) {
      return;
    }
    final category = _categories[_focusedCategoryIndex];
    if (!mounted) return;
    setState(() {
      _selectedCategory = category;
      _remoteMode = _RemoteMode.sidebarChannels;
      _closeAfterCategoryChannelSelection = true;
    });
    _filterChannels();
    final index =
        _filteredChannels.indexWhere((c) => c.url == _playingChannel?.url);
    setState(() => _focusedChannelIndex = index >= 0 ? index : 0);
    _resetSidebarTimer();
    _scrollToFocused();
  }

  Future<void> _hideFocusedLiveCategory() async {
    if (_focusedCategoryIndex < 0 ||
        _focusedCategoryIndex >= _categories.length) {
      return;
    }
    final category = _categories[_focusedCategoryIndex];
    if (!_isLockableLiveCategory(category)) return;
    final hidden = await hideCategoryWithParentalControl(
      context,
      settings: _settings,
      type: 'live',
      category: categoryLabel(category),
      profileId: categoryProfileId(category) ?? _settings.lastProfileId,
    );
    if (!mounted || !hidden) return;
    final channels =
        Provider.of<ChannelProvider>(context, listen: false).liveChannels;
    _updateCategories(channels);
    if (_playingChannel?.category == category) {
      final replacement = channels.cast<Channel?>().firstWhere(
            (channel) =>
                channel != null &&
                !_settings.isCategoryHidden(
                  'live',
                  categoryLabel(channel.category),
                  profileId: channel.sourceProfileId,
                ),
            orElse: () => null,
          );
      if (replacement != null) {
        _playingChannel = replacement;
        _settings.setLastWatchedChannelUrl(replacement.url);
        unawaited(_initializePlayer());
      }
    }
    setState(() {
      _selectedCategory = 'Tümü';
      _focusedCategoryIndex = 0;
    });
    _filterChannels();
    _resetSidebarTimer();
  }

  void _handleSidebarHeader(LogicalKeyboardKey key) {
    _resetSidebarTimer();
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_focusedHeaderIndex == 1) {
        setState(() => _focusedHeaderIndex = 0);
      } else {
        _closeSidebar();
      }
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_focusedHeaderIndex == 0) setState(() => _focusedHeaderIndex = 1);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _remoteMode = _RemoteMode.sidebarChannels;
        _focusedChannelIndex = 0;
      });
      _scrollToFocused();
      return;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      if (_focusedHeaderIndex == 0) {
        _searchFocusNode.requestFocus();
      } else {
        _showSettings(context);
      }
      return;
    }
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      _closeSidebar();
      return;
    }
  }

  void _handleSidebarFooter(LogicalKeyboardKey key) {
    _resetSidebarTimer();
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _remoteMode = _RemoteMode.sidebarChannels;
        _focusedChannelIndex =
            _filteredChannels.isNotEmpty ? _filteredChannels.length - 1 : 0;
      });
      _scrollToFocused();
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      _closeSidebar();
      return;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _openUserSelection();
      return;
    }
  }

  void _handleTopNav(LogicalKeyboardKey key) {
    final dur =
        _settings.autoHideDuration > 0 ? _settings.autoHideDuration : 3.0;
    if (key == LogicalKeyboardKey.arrowDown) {
      _topNavKey.currentState?.collapse();
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _topNavKey.currentState?.navigateLeft(dur);
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _topNavKey.currentState?.navigateRight(dur);
      return;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _topNavKey.currentState?.selectCurrent(context);
      return;
    }
  }

  void _openSidebar() {
    final playingChannel = _playingChannel;
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      if (playingChannel != null) {
        _selectedCategory = playingChannel.category;
      }
      _remoteMode = _RemoteMode.sidebarChannels;
    });
    _filterChannels();
    final idx =
        _filteredChannels.indexWhere((c) => c.url == playingChannel?.url);
    setState(() => _focusedChannelIndex = idx >= 0 ? idx : 0);
    _resetSidebarTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToFocused();
      _scrollToSelectedHorizontalCategory();
    });
  }

  void _closeSidebar() {
    setState(() {
      _remoteMode = _RemoteMode.watching;
      _closeAfterCategoryChannelSelection = false;
      _searchQuery = '';
      _searchController.clear();
      if (_playingChannel != null) {
        _selectedCategory = _playingChannel!.category;
      }
    });
    _filterChannels();
    final playingIndex =
        _filteredChannels.indexWhere((c) => c.url == _playingChannel?.url);
    if (mounted) {
      setState(
          () => _focusedChannelIndex = playingIndex >= 0 ? playingIndex : 0);
    }
    _hideSidebarTimer?.cancel();
  }

  void _openTopNav() {
    _topNavOpenedAt = DateTime.now();
    setState(() => _remoteMode = _RemoteMode.topNav);
    final dur =
        _settings.autoHideDuration > 0 ? _settings.autoHideDuration : 3.0;
    _topNavKey.currentState?.expandForRemote(dur);
  }

  bool _handleGlobalHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.audioVolumeUp ||
        key == LogicalKeyboardKey.numpadAdd ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.equal) {
      _adjustVolume(5.0);
      return true;
    }
    if (key == LogicalKeyboardKey.audioVolumeDown ||
        key == LogicalKeyboardKey.numpadSubtract ||
        key == LogicalKeyboardKey.minus) {
      _adjustVolume(-5.0);
      return true;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.audioVolumeMute ||
            key == LogicalKeyboardKey.f8 ||
            key == LogicalKeyboardKey.keyM)) {
      _toggleMute();
      return true;
    }
    return false;
  }

  void _adjustVolume(double delta) {
    final newVol = (_volume + delta).clamp(0.0, 100.0);
    _updateVolume(newVol);
  }

  void _updateVolume(double value) {
    setState(() => _volume = value);
    _playerEngine.setVolume(value);
    _showVolumeHUDTemp();
  }

  void _toggleMute() {
    if (_volume > 0) {
      _lastNonZeroVolume = _volume;
      _updateVolume(0);
    } else {
      _updateVolume(_lastNonZeroVolume);
    }
  }

  void _showVolumeHUDTemp() {
    setState(() => _showVolumeIndicator = true);
    _volumeIndicatorTimer?.cancel();
    _volumeIndicatorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showVolumeIndicator = false);
    });
  }

  String? _digitFromKey(LogicalKeyboardKey key) {
    final map = {
      LogicalKeyboardKey.digit0: '0',
      LogicalKeyboardKey.digit1: '1',
      LogicalKeyboardKey.digit2: '2',
      LogicalKeyboardKey.digit3: '3',
      LogicalKeyboardKey.digit4: '4',
      LogicalKeyboardKey.digit5: '5',
      LogicalKeyboardKey.digit6: '6',
      LogicalKeyboardKey.digit7: '7',
      LogicalKeyboardKey.digit8: '8',
      LogicalKeyboardKey.digit9: '9',
      LogicalKeyboardKey.numpad0: '0',
      LogicalKeyboardKey.numpad1: '1',
      LogicalKeyboardKey.numpad2: '2',
      LogicalKeyboardKey.numpad3: '3',
      LogicalKeyboardKey.numpad4: '4',
      LogicalKeyboardKey.numpad5: '5',
      LogicalKeyboardKey.numpad6: '6',
      LogicalKeyboardKey.numpad7: '7',
      LogicalKeyboardKey.numpad8: '8',
      LogicalKeyboardKey.numpad9: '9',
    };
    return map[key];
  }

  void _handleDirectChannelInput(String digit) {
    if (_channelNumberInput.length < 4) {
      setState(() => _channelNumberInput += digit);
    }
    _channelNumberTimer?.cancel();
    _channelNumberTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _channelNumberInput.isNotEmpty) {
        _submitChannelNumber();
      }
    });
  }

  void _submitChannelNumber() {
    _channelNumberTimer?.cancel();
    final number = int.tryParse(_channelNumberInput);
    setState(() => _channelNumberInput = '');
    if (number == null) return;

    final idx = number - 1;
    if (idx >= 0 && idx < _filteredChannels.length) {
      _changeChannel(idx);
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_settings.autoHideDuration == 0.0) return;
    if (_isMouseInControls) return;
    _hideControlsTimer = Timer(
        Duration(milliseconds: (_settings.autoHideDuration * 1000).toInt()),
        () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _startHideSidebarTimer() {
    _hideSidebarTimer?.cancel();
    if (_settings.autoHideDuration == 0.0) return;
    _hideSidebarTimer = Timer(
        Duration(milliseconds: (_settings.autoHideDuration * 1000).toInt()),
        () {
      if (mounted && (_showSidebar || _showRecentChannels)) {
        _closeSidebar();
      }
    });
  }

  void _resetSidebarTimer() {
    _startHideSidebarTimer();
  }

  void _filterChannels() {
    final allChannels =
        Provider.of<ChannelProvider>(context, listen: false).liveChannels;
    setState(() {
      _filteredChannels = allChannels.where((channel) {
        if (!_matchesSelectedProfile(channel)) return false;
        if (_settings.isCategoryHidden(
          'live',
          categoryLabel(channel.category),
          profileId: channel.sourceProfileId,
        )) {
          return false;
        }
        final matchesSearch =
            channel.name.toLowerCase().contains(_searchQuery.toLowerCase());
        bool matchesCategory;
        if (_searchQuery.isNotEmpty) {
          matchesCategory = true; // Search across all categories
        } else if (_selectedCategory == 'Tümü') {
          matchesCategory = true;
        } else if (_selectedCategory == 'Favoriler') {
          matchesCategory = _settings.isFavorite(
            'live',
            channel.url,
            profileId: channel.sourceProfileId,
          );
        } else {
          matchesCategory = channel.category == _selectedCategory;
        }
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  void _scrollToSelected() {
    if (!mounted) return;
    final idx =
        _filteredChannels.indexWhere((c) => c.url == _playingChannel?.url);
    if (idx == -1) return;
    // Only update focus if sidebar is open
    if (_remoteMode == _RemoteMode.sidebarChannels) {
      setState(() {
        _focusedChannelIndex = idx;
      });
    }
    _scrollToFocused();
  }

  void _scrollToSelectedHorizontalCategory() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _categoryKeys[_selectedCategory];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          alignment: 0.5,
          duration: Duration.zero,
        );
      }
    });
  }

  void _scrollToSelectedCategoryInSidebar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _categories.indexOf(_selectedCategory);
      if (index >= 0) _scrollToCategoryIndex(index);
    });
  }

  void _scrollToCategoryIndex(int idx) {
    if (!_categorySidebarScrollController.hasClients ||
        idx < 0 ||
        idx >= _categories.length) {
      return;
    }
    final position = _categorySidebarScrollController.position;
    final itemCenter = idx * _categoryItemH + (_categoryItemH / 2);
    final target = itemCenter - (position.viewportDimension / 2);
    _categorySidebarScrollController
        .jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  void _scrollToProfileIndex(int idx) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_profileSidebarScrollController.hasClients) return;
      final profiles = _profileFilters;
      if (idx < 0 || idx >= profiles.length) return;
      final position = _profileSidebarScrollController.position;
      final itemCenter = idx * _categoryItemH + (_categoryItemH / 2);
      final target = itemCenter - (position.viewportDimension / 2);
      _profileSidebarScrollController.jumpTo(
        target.clamp(0.0, position.maxScrollExtent),
      );
    });
  }

  void _onScreenTap() {
    FocusScope.of(context).requestFocus(_keyboardFocusNode);
    if (_remoteMode == _RemoteMode.watching) {
      setState(() {
        _showControls = !_showControls;
        if (_showControls) _startHideControlsTimer();
      });
    } else {
      _closeSidebar();
    }
  }

  void _onScreenHover(PointerEvent details) {
    final size = MediaQuery.of(context).size;
    final double x = details.localPosition.dx;
    final double y = details.localPosition.dy;

    if (x < 40 && _remoteMode == _RemoteMode.watching) {
      setState(() => _remoteMode = _RemoteMode.sidebarChannels);
      _resetSidebarTimer();
    }
    if (y > (size.height - 60) && !_showControls) {
      setState(() => _showControls = true);
    }
    if (x < 320) {
      _isMouseInSidebar = true;
      _hideSidebarTimer?.cancel();
    } else {
      if (_isMouseInSidebar) {
        _isMouseInSidebar = false;
        _startHideSidebarTimer();
      }
    }
    if (y > (size.height - 200)) {
      _startHideControlsTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleGlobalHardwareKey);
    LocalCompanionService.channelPlayRequest.removeListener(
      _handlePhoneChannelPlayRequest,
    );
    LocalCompanionService.contentPlayRequest.removeListener(
      _handlePhoneContentPlayRequest,
    );
    LocalCompanionService.contentPlaybackClosed.removeListener(
      _handlePhoneContentClosed,
    );
    LocalCompanionService.vodPlaybackDepth.removeListener(
      _handleVodPlaybackDepthChanged,
    );
    _channelProvider?.removeListener(_handleCatalogChanged);
    _hideSidebarTimer?.cancel();
    _hideControlsTimer?.cancel();
    _volumeIndicatorTimer?.cancel();
    _bufferingDebounceTimer?.cancel();
    _streamRecoveryTimer?.cancel();
    _streamRecoveryResetTimer?.cancel();
    _epgRefreshTimer?.cancel();
    _channelNumberTimer?.cancel();
    _favoriteLongPress.cancel();
    _categoryLongPress.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _diagSub?.cancel();
    _bufferSub?.cancel();
    unawaited(_disposePlayerAndRestoreDisplay());
    _scrollController.dispose();
    _categoryScrollController.dispose();
    _categorySidebarScrollController.dispose();
    _profileSidebarScrollController.dispose();
    _recentChannelsScrollController.dispose();
    _keyboardFocusNode.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _disposePlayerAndRestoreDisplay() async {
    await _playerEngine.dispose();
    await AppPlayerEngine.restoreDisplayMode();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _resumePlaybackAfterLifecyclePause = _isPlaying;
      _playerEngine.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (_resumePlaybackAfterLifecyclePause) {
        _playerEngine.play();
      }
      _resumePlaybackAfterLifecyclePause = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (_searchFocusNode.hasFocus) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          _resetSidebarTimer();
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _searchFocusNode.unfocus();
            setState(() {
              _remoteMode = _RemoteMode.sidebarChannels;
              _focusedChannelIndex = 0;
            });
            _scrollToFocused();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            _searchFocusNode.unfocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult
              .ignored; // Let text field handle left/right and typing
        }

        final isSelectKey = event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter;
        if (isSelectKey &&
            event is KeyDownEvent &&
            _remoteMode == _RemoteMode.sidebarChannels) {
          _hideSidebarTimer?.cancel();
        }
        if (_favoriteLongPress.handle(
          event,
          enabled: _remoteMode == _RemoteMode.sidebarChannels &&
              _filteredChannels.isNotEmpty,
          onShortPress: () => _changeChannel(_focusedChannelIndex),
          onLongPress: _toggleFocusedChannelFavorite,
        )) {
          return KeyEventResult.handled;
        }
        if (_categoryLongPress.handle(
          event,
          enabled: _remoteMode == _RemoteMode.sidebarCategories &&
              _categories.isNotEmpty,
          onShortPress: () => unawaited(_activateFocusedLiveCategory()),
          onLongPress: () {
            _categoryLongPress.cancel();
            unawaited(_hideFocusedLiveCategory());
          },
        )) {
          return KeyEventResult.handled;
        }

        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape) {
          final now = DateTime.now();
          if (_lastModalClosedAt != null &&
              now.difference(_lastModalClosedAt!) <
                  const Duration(milliseconds: 300)) {
            return KeyEventResult.handled;
          }

          if (_remoteMode == _RemoteMode.topNav) {
            if (_topNavOpenedAt != null &&
                now.difference(_topNavOpenedAt!) <
                    const Duration(milliseconds: 300)) {
              return KeyEventResult.handled;
            }
            _playerEngine.stop();
            SystemNavigator.pop();
            return KeyEventResult.handled;
          } else {
            _handleKeyEvent(event);
            return KeyEventResult.handled;
          }
        }

        _handleKeyEvent(event);
        if (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.mediaFastForward ||
            key == LogicalKeyboardKey.mediaRewind ||
            key == LogicalKeyboardKey.pageUp ||
            key == LogicalKeyboardKey.pageDown ||
            key == LogicalKeyboardKey.audioVolumeUp ||
            key == LogicalKeyboardKey.audioVolumeDown ||
            key == LogicalKeyboardKey.audioVolumeMute ||
            key == LogicalKeyboardKey.numpadAdd ||
            key == LogicalKeyboardKey.add ||
            key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.numpadSubtract ||
            key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.keyM) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              final now = DateTime.now();
              if (_lastModalClosedAt != null &&
                  now.difference(_lastModalClosedAt!) <
                      const Duration(milliseconds: 300)) {
                return;
              }
              if (_remoteMode == _RemoteMode.topNav) {
                if (_topNavOpenedAt != null &&
                    now.difference(_topNavOpenedAt!) <
                        const Duration(milliseconds: 300)) {
                  return;
                }
                _playerEngine.stop();
                SystemNavigator.pop();
              } else {
                _openTopNav();
              }
            },
            child: Scaffold(
              backgroundColor: (_playerEngine.engineType ==
                          PlayerEngineType.exoPlayer ||
                      _playerEngine.engineType == PlayerEngineType.fireTvMedia3)
                  ? Colors.transparent
                  : Colors.black,
              body: MouseRegion(
                onHover: _onScreenHover,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: RepaintBoundary(
                          child: ExcludeFocus(
                              child:
                                  AppVideoWidget(playerEngine: _playerEngine)),
                        ),
                      ),
                    ),
                    DiagnosticsOverlayWidget(
                      diagnostics: _diagnostics,
                      visible: _settings.showDiagnostics,
                    ),
                    if (_playbackError == null &&
                        _diagnostics.renderedFrames <= 0 &&
                        (!_isPlaying || _isBuffering))
                      Positioned.fill(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: _settings.primaryColor,
                          ),
                        ),
                      ),
                    if (_playbackError != null)
                      Positioned(
                        right: 24,
                        bottom: 24,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Text(
                              _playbackError!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: Duration.zero,
                          color: Colors.black.withValues(
                              alpha: (1.0 - _brightness).clamp(0.0, 0.9)),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _onScreenTap,
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: Duration.zero,
                      curve: Curves.easeOutCubic,
                      left: _showSidebar ? 0 : -320,
                      top: 0,
                      bottom: 0,
                      child: MouseRegion(
                        onEnter: (_) {
                          setState(() => _isMouseInSidebar = true);
                        },
                        onExit: (_) {
                          setState(() => _isMouseInSidebar = false);
                          _startHideSidebarTimer();
                        },
                        child: _buildSidebar(),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: Duration.zero,
                      curve: Curves.easeOutCubic,
                      right: _showRecentChannels ? 0 : -170,
                      top: ((MediaQuery.sizeOf(context).height -
                                  (106 +
                                      (_resolvedRecentChannels()
                                              .length
                                              .clamp(1, 8) *
                                          48))) /
                              2)
                          .clamp(0.0, double.infinity),
                      width: 150,
                      height: (106 +
                              (_resolvedRecentChannels().length.clamp(1, 8) *
                                  48))
                          .toDouble(),
                      child: _buildRecentChannelsPanel(),
                    ),
                    AnimatedPositioned(
                      duration: Duration.zero,
                      bottom: _showControls ? 0 : -200,
                      left: _showSidebar ? 320 : 0,
                      right: 0,
                      child: MouseRegion(
                        onEnter: (_) {
                          setState(() {
                            _isMouseInControls = true;
                            _showControls = true;
                          });
                          _hideControlsTimer?.cancel();
                        },
                        onExit: (_) {
                          setState(() => _isMouseInControls = false);
                          _startHideControlsTimer();
                        },
                        child: _buildVideoControls(),
                      ),
                    ),
                    SafeArea(
                      child: TopNavBar(
                        key: _topNavKey,
                        activeScreen: 'live_tv',
                        onDismiss: () {
                          if (mounted && _remoteMode == _RemoteMode.topNav) {
                            setState(() => _remoteMode = _RemoteMode.watching);
                          }
                        },
                      ),
                    ),
                    if (_channelNumberInput.isNotEmpty)
                      Positioned(
                        top: 40,
                        right: 40,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: _settings.primaryColor
                                    .withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            _channelNumberInput,
                            style: GoogleFonts.splineSans(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 4.0,
                            ),
                          ),
                        ),
                      ),
                    if (_showVolumeIndicator) _buildVolumeHUD(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color:
            const Color(0xFF0F0C1D).withValues(alpha: _settings.sidebarOpacity),
        boxShadow: [
          if (_showSidebar)
            BoxShadow(
                color: Colors.black
                    .withValues(alpha: 0.5 * _settings.sidebarOpacity),
                blurRadius: 40,
                offset: const Offset(10, 0))
        ],
      ),
      child: Column(
        children: [
          _buildSidebarHeader(),
          _buildHorizontalCategorySelector(),
          Expanded(
            child: Stack(
              children: [
                Opacity(
                  opacity:
                      (_showCategoriesSidebar || _showProfilesSidebar) ? 0 : 1,
                  child: IgnorePointer(
                      ignoring: _showCategoriesSidebar || _showProfilesSidebar,
                      child: _buildChannelList()),
                ),
                if (_showCategoriesSidebar) _buildCategoriesPanel(),
                if (_showProfilesSidebar) _buildProfilesPanel(),
              ],
            ),
          ),
          _buildSidebarFooter(),
        ],
      ),
    );
  }

  Widget _buildRecentChannelsPanel() {
    final recent = _resolvedRecentChannels();
    final channels =
        Provider.of<ChannelProvider>(context, listen: false).liveChannels;
    final channelNumbers = <String, int>{
      for (var index = 0; index < channels.length; index++)
        channels[index].url: index + 1,
    };
    final opacity = _settings.sidebarOpacity;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F0C1D).withValues(alpha: opacity),
          borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(14)),
          border: Border(
            left: BorderSide(
              color: Colors.white.withValues(alpha: 0.12 * opacity),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(14)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 14, 14, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 16,
                      color: _settings.primaryColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _settings.getText('recent_channels'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSans(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.1 * opacity),
              ),
              Expanded(
                child: recent.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            _settings.getText('no_recent_channels'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _recentChannelsScrollController,
                        padding: const EdgeInsets.fromLTRB(5, 8, 12, 8),
                        itemExtent: 48,
                        itemCount: recent.length,
                        itemBuilder: (context, index) {
                          final channel = recent[index];
                          final focused = _showRecentChannels &&
                              index == _focusedRecentChannelIndex;
                          final playing = channel.url == _playingChannel?.url;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: AnimatedContainer(
                              duration: Duration.zero,
                              padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
                              decoration: BoxDecoration(
                                color: focused
                                    ? _settings.primaryColor
                                        .withValues(alpha: 0.2 * opacity)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: focused
                                      ? Colors.white
                                      : Colors.white.withValues(
                                          alpha: 0.04 * opacity,
                                        ),
                                  width: focused ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 21,
                                    child: Text(
                                      channelNumbers[channel.url]?.toString() ??
                                          '•',
                                      style: TextStyle(
                                        color: focused
                                            ? Colors.white
                                            : Colors.white54,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      channel.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: focused
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (playing)
                                    Icon(
                                      Icons.play_arrow_rounded,
                                      size: 14,
                                      color: _settings.primaryColor,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarHeader() {
    final isSearchFocused =
        _remoteMode == _RemoteMode.sidebarHeader && _focusedHeaderIndex == 0;
    final isSettingsFocused =
        _remoteMode == _RemoteMode.sidebarHeader && _focusedHeaderIndex == 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
                (_showCategoriesSidebar || _showProfilesSidebar)
                    ? Icons.menu_open
                    : Icons.menu,
                color: (_showCategoriesSidebar || _showProfilesSidebar)
                    ? _settings.primaryColor
                    : Colors.white,
                size: 22),
            onPressed: () {
              setState(() {
                if (_remoteMode == _RemoteMode.sidebarCategories ||
                    _remoteMode == _RemoteMode.sidebarProfiles) {
                  _remoteMode = _RemoteMode.sidebarChannels;
                } else {
                  _remoteMode = _RemoteMode.sidebarCategories;
                  _focusedCategoryIndex =
                      _categories.indexOf(_selectedCategory);
                  if (_focusedCategoryIndex < 0) _focusedCategoryIndex = 0;
                }
              });
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1D1933)
                    .withValues(alpha: 0.5 * _settings.sidebarOpacity),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                    color: isSearchFocused
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.08),
                    width: isSearchFocused ? 2 : 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.search,
                      color: Colors.white.withValues(alpha: 0.4), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                          if (value.isEmpty && _playingChannel != null) {
                            _selectedCategory = _playingChannel!.category;
                          }
                          _filterChannels();
                        });
                      },
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: _settings.getText('search_hint'),
                        hintStyle: GoogleFonts.notoSans(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 13),
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: isSettingsFocused
                  ? Border.all(color: Colors.white, width: 2)
                  : Border.all(color: Colors.transparent, width: 2),
            ),
            child: IconButton(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              icon: Icon(Icons.settings,
                  color: isSettingsFocused ? Colors.white : Colors.grey,
                  size: 20),
              onPressed: () => _showSettings(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalCategorySelector() {
    return Container(
      height: 29,
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: ListView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(10000),
        controller: _categoryScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == _selectedCategory;
          if (!_categoryKeys.containsKey(cat)) _categoryKeys[cat] = GlobalKey();
          return Padding(
            key: _categoryKeys[cat],
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              canRequestFocus: false,
              onTap: () {
                setState(() {
                  _selectedCategory = cat;
                  _filterChannels();
                });
                _scrollToSelectedHorizontalCategory();
                final idx = _filteredChannels
                    .indexWhere((c) => c.url == _playingChannel?.url);
                if (_remoteMode == _RemoteMode.sidebarChannels) {
                  setState(() {
                    _focusedChannelIndex = idx >= 0 ? idx : 0;
                  });
                }
                _scrollToFocused();
              },
              borderRadius: BorderRadius.circular(17),
              child: AnimatedContainer(
                duration: Duration.zero,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _settings.primaryColor
                          .withValues(alpha: _settings.sidebarOpacity)
                      : Colors.white
                          .withValues(alpha: 0.05 * _settings.sidebarOpacity),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                      color: isSelected
                          ? _settings.primaryColor
                          : Colors.white.withValues(alpha: 0.1),
                      width: 1),
                ),
                child: Center(
                  child: Text(categoryLabel(cat),
                      style: GoogleFonts.notoSans(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      )),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChannelList() {
    if (_filteredChannels.isEmpty) {
      final isLoading = Provider.of<ChannelProvider>(context).isLoading;
      if (isLoading) return const Center(child: CircularProgressIndicator());
      return Center(
          child: Text(_settings.getText('no_channel_found'),
              style: GoogleFonts.notoSans(color: Colors.grey)));
    }
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          itemExtent: _itemH,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _filteredChannels.length,
          itemBuilder: (context, index) {
            final channel = _filteredChannels[index];
            final isFavorite = _settings.isFavorite(
              'live',
              channel.url,
              profileId: channel.sourceProfileId,
            );
            final isPlaying = _playingChannel?.url == channel.url;
            final isFocused = _focusedChannelIndex == index;
            return InkWell(
              canRequestFocus: false,
              onTap: () => _changeChannel(index),
              onLongPress: () {
                setState(() {
                  _settings.toggleFavorite(
                    'live',
                    channel.url,
                    profileId: channel.sourceProfileId,
                  );
                  if (_selectedCategory == 'Favoriler') _filterChannels();
                });
                _refreshLiveCategoryCounts();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: isPlaying
                      ? _settings.primaryColor
                          .withValues(alpha: 0.2 * _settings.sidebarOpacity)
                      : (isFocused
                          ? Colors.white.withValues(
                              alpha: 0.08 * _settings.sidebarOpacity)
                          : const Color(0xFF1E1933).withValues(
                              alpha: 0.5 * _settings.sidebarOpacity)),
                  borderRadius: BorderRadius.circular(8),
                  border: isFocused
                      ? Border.all(color: Colors.white, width: 2)
                      : (isPlaying
                          ? Border.all(
                              color:
                                  _settings.primaryColor.withValues(alpha: 0.5))
                          : Border.all(color: Colors.transparent)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        "${index + 1}",
                        style: GoogleFonts.splineSans(
                          color: (isPlaying || isFocused)
                              ? Colors.white
                              : Colors.white54,
                          fontWeight: (isPlaying || isFocused)
                              ? FontWeight.bold
                              : FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        channel.name,
                        style: GoogleFonts.splineSans(
                          color: (isPlaying || isFocused)
                              ? Colors.white
                              : Colors.grey[300],
                          fontWeight: (isPlaying || isFocused)
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isFavorite)
                      const Icon(Icons.favorite, color: Colors.red, size: 14),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCategoriesPanel() {
    return Container(
      color:
          const Color(0xFF161325).withValues(alpha: _settings.sidebarOpacity),
      child: ListView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(5000),
        controller: _categorySidebarScrollController,
        itemExtent: _categoryItemH,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == _selectedCategory;
          final isFocused = _focusedCategoryIndex == index;
          if (!_categorySidebarKeys.containsKey(cat)) {
            _categorySidebarKeys[cat] = GlobalKey();
          }
          return InkWell(
            canRequestFocus: false,
            key: _categorySidebarKeys[cat],
            onTap: () {
              setState(() => _focusedCategoryIndex = index);
              unawaited(_activateFocusedLiveCategory());
            },
            child: AnimatedContainer(
              duration: Duration.zero,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? _settings.primaryColor
                        .withValues(alpha: 0.15 * _settings.sidebarOpacity)
                    : (isFocused
                        ? Colors.white
                            .withValues(alpha: 0.08 * _settings.sidebarOpacity)
                        : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
                border: isFocused
                    ? Border.all(color: Colors.white, width: 2)
                    : (isSelected
                        ? Border.all(
                            color:
                                _settings.primaryColor.withValues(alpha: 0.3))
                        : null),
              ),
              child: Row(
                children: [
                  if (isSelected)
                    Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                            color: _settings.primaryColor,
                            borderRadius: BorderRadius.circular(2))),
                  if (isSelected) const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${categoryProfileId(cat) == null ? _settings.getText(_getCategoryKey(cat)) : categoryLabel(cat)} '
                      '(${_liveCategoryCount(cat)})',
                      style: GoogleFonts.notoSans(
                        color: isSelected || isFocused
                            ? Colors.white
                            : Colors.grey[400],
                        fontSize: 13,
                        fontWeight: isSelected || isFocused
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle,
                        color: _settings.primaryColor, size: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfilesPanel() {
    final profiles = _profileFilters;
    return Container(
      color:
          const Color(0xFF12101F).withValues(alpha: _settings.sidebarOpacity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.people_alt_outlined,
                    color: Colors.white70, size: 18),
                const SizedBox(width: 10),
                Text(
                  _settings.getText('user_selection').toUpperCase(),
                  style: GoogleFonts.notoSans(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _profileSidebarScrollController,
              itemExtent: _categoryItemH,
              itemCount: profiles.length,
              itemBuilder: (context, index) {
                final profile = profiles[index];
                final profileId = profile?.id;
                final isSelected = profileId == _selectedProfileId;
                final isFocused = _focusedProfileIndex == index;
                final title = profile?.name ?? _settings.getText('all');
                return InkWell(
                  canRequestFocus: false,
                  onTap: () {
                    setState(() => _focusedProfileIndex = index);
                    _activateFocusedProfile();
                  },
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _settings.primaryColor.withValues(
                              alpha: 0.15 * _settings.sidebarOpacity,
                            )
                          : (isFocused
                              ? Colors.white.withValues(
                                  alpha: 0.08 * _settings.sidebarOpacity,
                                )
                              : Colors.transparent),
                      borderRadius: BorderRadius.circular(12),
                      border: isFocused
                          ? Border.all(color: Colors.white, width: 2)
                          : (isSelected
                              ? Border.all(
                                  color: _settings.primaryColor
                                      .withValues(alpha: 0.3),
                                )
                              : null),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: isSelected || isFocused
                              ? _settings.primaryColor
                              : Colors.white12,
                          child: profile == null
                              ? const Icon(Icons.people_alt_rounded,
                                  color: Colors.white, size: 15)
                              : Text(
                                  profile.initial,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            '$title (${_profileChannelCount(profileId)})',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSans(
                              color: isSelected || isFocused
                                  ? Colors.white
                                  : Colors.grey[400],
                              fontSize: 13,
                              fontWeight: isSelected || isFocused
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: _settings.primaryColor,
                            size: 16,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarFooter() {
    Profile? currentProfile;
    String? sourceProfileId;
    if (_remoteMode == _RemoteMode.sidebarProfiles) {
      sourceProfileId = _selectedProfileId;
    } else if (_remoteMode == _RemoteMode.sidebarCategories) {
      final focusedCategory = _focusedCategoryIndex >= 0 &&
              _focusedCategoryIndex < _categories.length
          ? _categories[_focusedCategoryIndex]
          : _selectedCategory;
      sourceProfileId = categoryProfileId(focusedCategory);
    } else if (_filteredChannels.isNotEmpty &&
        _focusedChannelIndex >= 0 &&
        _focusedChannelIndex < _filteredChannels.length) {
      sourceProfileId = _filteredChannels[_focusedChannelIndex].sourceProfileId;
    }
    sourceProfileId ??= _playingChannel?.sourceProfileId;
    sourceProfileId ??= _settings.lastProfileId;
    if (sourceProfileId != null) {
      try {
        currentProfile =
            _settings.profiles.firstWhere((p) => p.id == sourceProfileId);
      } catch (_) {}
    }
    final isFocused = _remoteMode == _RemoteMode.sidebarFooter;
    return GestureDetector(
      onTap: () {
        _openUserSelection();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
        decoration: BoxDecoration(
          border: const Border(top: BorderSide(color: Colors.white10)),
          color: isFocused
              ? Colors.white.withValues(alpha: 0.1 * _settings.sidebarOpacity)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: isFocused
                  ? Colors.white
                  : _settings.primaryColor.withValues(alpha: 0.2),
              child: Text(currentProfile?.initial ?? '?',
                  style: TextStyle(
                      color: isFocused ? Colors.black : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(currentProfile?.name ?? 'Misafir',
                    style: TextStyle(
                        color: isFocused ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 13))),
            Icon(Icons.person_outline,
                color: isFocused ? Colors.white : Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoControls() {
    if (_playingChannel == null) return const SizedBox.shrink();
    final ch = _playingChannel!;
    final int idx = _filteredChannels.indexOf(ch);
    final String displayText = idx != -1 ? '${idx + 1}. ${ch.name}' : ch.name;

    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: _settings.sidebarOpacity),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Colors.white
                  .withValues(alpha: 0.15 * _settings.sidebarOpacity)),
          boxShadow: [
            BoxShadow(
                color: Colors.black
                    .withValues(alpha: 0.5 * _settings.sidebarOpacity),
                blurRadius: 20,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayText,
              style: GoogleFonts.notoSans(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_currentProgramTitle?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 3),
              Text(
                _currentProgramTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSans(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeHUD() {
    return Positioned(
      right: 32,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          width: 44,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_volume > 0 ? Icons.volume_up : Icons.volume_off,
                  color: Colors.white, size: 18),
              const SizedBox(height: 8),
              Expanded(
                child: RotatedBox(
                  quarterTurns: -1,
                  child: SliderTheme(
                    data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 5),
                        activeTrackColor: _settings.primaryColor,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white),
                    child: Slider(
                        value: _volume,
                        min: 0,
                        max: 100,
                        onChanged: _updateVolume),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('${_volume.round()}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSettings(BuildContext context) async {
    final engineBefore = _settings.preferredEngine;
    final liveRefreshRateBefore = _settings.liveTvRefreshRate;
    Profile? currentProfile;
    if (_settings.lastProfileId != null) {
      try {
        currentProfile = _settings.profiles
            .firstWhere((p) => p.id == _settings.lastProfileId);
      } catch (_) {}
    }
    final result = await showInstantDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => SettingsOverlay(profile: currentProfile),
    );
    _lastModalClosedAt = DateTime.now();
    if (mounted) {
      final channels = Provider.of<ChannelProvider>(this.context, listen: false)
          .liveChannels;
      _updateCategories(channels);
      if (!_categories.contains(_selectedCategory)) {
        _selectedCategory = 'Tümü';
      }
      _filterChannels();
    }
    if (_settings.liveTvRefreshRate != liveRefreshRateBefore) {
      _liveDisplayPreparation = AppPlayerEngine.prepareLiveDisplayModeAndWait(
        refreshRate: _settings.liveTvRefreshRate,
      );
      await _liveDisplayPreparation;
    }
    if (_settings.preferredEngine != engineBefore) {
      await _initializePlayer();
    }
    if (result == 'open_profiles') {
      await _openUserSelection();
    }
  }

  Future<void> _openUserSelection() async {
    _playerEngine.pause(); // Pause video while selecting
    await Navigator.push(context,
        MaterialPageRoute(builder: (context) => const UserSelectionScreen()));
    if (!mounted) return;
    _lastModalClosedAt = DateTime.now();
    final provider = Provider.of<ChannelProvider>(context, listen: false);
    if (mounted) {
      _updateCategories(provider.liveChannels);

      bool stillExists = false;
      if (_playingChannel != null) {
        stillExists =
            provider.liveChannels.any((c) => c.url == _playingChannel!.url);
      }

      if (!stillExists && provider.liveChannels.isNotEmpty) {
        Channel initialChannel = provider.liveChannels[0];
        if (_settings.lastWatchedChannelUrl != null) {
          try {
            initialChannel = provider.liveChannels
                .firstWhere((c) => c.url == _settings.lastWatchedChannelUrl);
          } catch (_) {}
        }
        _selectedCategory = initialChannel.category;
        _playingChannel = initialChannel;
        _filterChannels();
        setState(() {});
        await _initializePlayer(); // Starts the new channel
      } else {
        _filterChannels();
        setState(() {});
        await _playerEngine.play(); // Resume the existing channel
      }
    }
  }
}
