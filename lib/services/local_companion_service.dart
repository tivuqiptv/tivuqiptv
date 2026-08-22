import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';
import '../models/channel.dart';
import '../providers/channel_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/watch_history_provider.dart';
import '../utils/scoped_category.dart';

class LocalCompanionService {
  LocalCompanionService(this._settings, this._channels, this._history);

  static const MethodChannel channel = MethodChannel(
    'com.tivuq.iptv/local_companion',
  );
  static final ValueNotifier<Profile?> receivedProfile =
      ValueNotifier<Profile?>(null);
  static final ValueNotifier<LocalPairingPrompt?> pairingPrompt =
      ValueNotifier<LocalPairingPrompt?>(null);
  static final ValueNotifier<LocalChannelPlayRequest?> channelPlayRequest =
      ValueNotifier<LocalChannelPlayRequest?>(null);
  static final ValueNotifier<LocalContentPlayRequest?> contentPlayRequest =
      ValueNotifier<LocalContentPlayRequest?>(null);
  static final ValueNotifier<int> contentPlaybackClosed = ValueNotifier<int>(0);
  static final ValueNotifier<int> vodPlaybackDepth = ValueNotifier<int>(0);
  static bool liveTvTransitionInProgress = false;
  static final ValueNotifier<int> liveRecentChannelsRevision =
      ValueNotifier<int>(0);

  final SettingsProvider _settings;
  final ChannelProvider _channels;
  final WatchHistoryProvider _history;
  Timer? _pairingPromptTimer;
  Timer? _catalogPublishTimer;
  Timer? _settingsPublishTimer;
  late int _lastSettingsRevision;
  late int _lastVisibilityRevision;
  late int _lastMembershipRevision;
  late int _lastHistoryRevision;
  int _playRequestSequence = 0;
  int _catalogPublishGeneration = 0;
  final Map<String, Channel> _remoteMovies = {};
  final Map<String, Channel> _remoteSeries = {};
  final Map<String, LocalEpisodeSelection> _remoteEpisodes = {};

  void initialize() {
    _lastSettingsRevision = _settings.companionSettingsRevision;
    _lastVisibilityRevision = _settings.catalogVisibilityRevision;
    _lastMembershipRevision = _settings.catalogMembershipRevision;
    _lastHistoryRevision = _history.recentRevision;
    _channels.addListener(_scheduleCatalogPublish);
    _settings.addListener(_handleSettingsChanged);
    _history.addListener(_handleHistoryChanged);
    liveRecentChannelsRevision.addListener(_scheduleCatalogPublish);
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'profileReceived':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          await _saveReceivedProfile(
            args['name']?.toString() ?? '',
            args['playlistUrl']?.toString() ?? '',
            profileId: args['profileId']?.toString(),
          );
          return true;
        case 'profilesRequested':
          return _settings.profiles
              .map(
                (profile) => <String, dynamic>{
                  'id': profile.id,
                  'name': profile.name,
                  'playlistUrl': profile.m3uUrl ?? '',
                },
              )
              .toList(growable: false);
        case 'pairedDevicesChanged':
          _clearPairingPrompt();
          return true;
        case 'pairingCodeRequested':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          _showPairingPrompt(args);
          return true;
        case 'channelPlayRequested':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final id = args['id']?.toString().trim() ?? '';
          if (id.isNotEmpty) {
            channelPlayRequest.value = LocalChannelPlayRequest(
              id: id,
              sequence: ++_playRequestSequence,
            );
          }
          return true;
        case 'settingsUpdateRequested':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          await _applySettingsUpdate(args);
          return true;
        case 'seriesEpisodesRequested':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          return _loadRemoteSeriesEpisodes(args['id']?.toString() ?? '');
        case 'contentPlayRequested':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          _handleRemoteContentPlay(args['id']?.toString() ?? '');
          return true;
        default:
          return null;
      }
    });
    _scheduleCatalogPublish();
    _scheduleSettingsPublish();
  }

  void _handleSettingsChanged() {
    final settingsRevision = _settings.companionSettingsRevision;
    if (settingsRevision != _lastSettingsRevision) {
      _lastSettingsRevision = settingsRevision;
      _scheduleSettingsPublish();
    }
    final visibilityRevision = _settings.catalogVisibilityRevision;
    if (visibilityRevision != _lastVisibilityRevision) {
      _lastVisibilityRevision = visibilityRevision;
      _scheduleCatalogPublish();
    }
    final membershipRevision = _settings.catalogMembershipRevision;
    if (membershipRevision != _lastMembershipRevision) {
      _lastMembershipRevision = membershipRevision;
      _scheduleCatalogPublish();
    }
  }

  void _handleHistoryChanged() {
    final historyRevision = _history.recentRevision;
    if (historyRevision == _lastHistoryRevision) return;
    _lastHistoryRevision = historyRevision;
    _scheduleCatalogPublish();
  }

  void _scheduleSettingsPublish() {
    _settingsPublishTimer?.cancel();
    _settingsPublishTimer = Timer(
      const Duration(milliseconds: 250),
      _publishAppSettings,
    );
  }

  Future<void> _publishAppSettings() async {
    try {
      await channel.invokeMethod<void>('publishAppSettings', {
        'settings': {
          'sidebarOpacity': _settings.sidebarOpacity,
          'autoHideDuration': _settings.autoHideDuration,
          'quality': _settings.quality,
          'startupScreen': _settings.startupScreen,
          'liveTvRefreshRate': _settings.liveTvRefreshRate,
          'enableTunneling': _settings.enableTunneling,
          'autoStartOnBoot': _settings.autoStartOnBoot,
        },
      });
    } on MissingPluginException {
      // Yerel ayar köprüsü yalnızca Android/Fire TV'de bulunur.
    } on PlatformException catch (error) {
      debugPrint('Telefon ayarları yayınlanamadı: ${error.code}');
    }
  }

  Future<void> _applySettingsUpdate(Map<String, dynamic> values) async {
    final opacity = (values['sidebarOpacity'] as num?)?.toDouble();
    final hideDuration = (values['autoHideDuration'] as num?)?.toDouble();
    final refreshRate = (values['liveTvRefreshRate'] as num?)?.toInt();
    final quality = values['quality']?.toString();
    final startupScreen = values['startupScreen']?.toString();
    await _settings.updateSettings(
      sidebarOpacity:
          opacity != null && opacity >= 0.05 && opacity <= 1 ? opacity : null,
      autoHideDuration: {0.0, 2.0, 3.0, 5.0, 8.0, 10.0}.contains(hideDuration)
          ? hideDuration
          : null,
      quality: const {'auto', '4k', '1080p', '720p'}.contains(quality)
          ? quality
          : null,
      startupScreen: const {
        'live_tv',
        'movies',
        'series',
        'last_screen',
      }.contains(startupScreen)
          ? startupScreen
          : null,
      liveTvRefreshRate:
          refreshRate == 50 || refreshRate == 60 ? refreshRate : null,
      enableTunneling: values['enableTunneling'] is bool
          ? values['enableTunneling'] as bool
          : null,
      autoStartOnBoot: values['autoStartOnBoot'] is bool
          ? values['autoStartOnBoot'] as bool
          : null,
    );
  }

  void _scheduleCatalogPublish() {
    _catalogPublishTimer?.cancel();
    final generation = ++_catalogPublishGeneration;
    _catalogPublishTimer = Timer(
      const Duration(milliseconds: 900),
      () => _publishCatalogsInChunks(generation),
    );
  }

  Future<void> _publishCatalogsInChunks(int generation) async {
    try {
      final recentLiveUrls = await _recentLiveChannelOrder();
      final updateId = '${DateTime.now().microsecondsSinceEpoch}-$generation';
      await channel.invokeMethod<void>('beginLiveChannelsUpdate', {
        'updateId': updateId,
      });
      const chunkSize = 120;
      final liveChannels = _channels.liveChannels;
      for (var start = 0; start < liveChannels.length; start += chunkSize) {
        if (generation != _catalogPublishGeneration) return;
        final end = (start + chunkSize).clamp(0, liveChannels.length);
        final chunk = <Map<String, dynamic>>[];
        for (var index = start; index < end; index++) {
          final item = liveChannels[index];
          if (_settings.isCategoryHidden(
            'live',
            categoryLabel(item.category),
            profileId: item.sourceProfileId,
          )) {
            continue;
          }
          chunk.add({
            'id': channelRemoteId(item),
            'name': item.name,
            'category': categoryLabel(item.category),
            'profileName': item.sourceProfileName ?? '',
            'isFavorite': _settings.isFavorite(
              'live',
              item.url,
              profileId: item.sourceProfileId,
            ),
            'isRecentlyWatched': recentLiveUrls.containsKey(item.url),
            'recentOrder': recentLiveUrls[item.url] ?? -1,
          });
        }
        await channel.invokeMethod<void>('appendLiveChannelsUpdate', {
          'updateId': updateId,
          'channels': chunk,
        });
        await Future<void>.delayed(const Duration(milliseconds: 12));
      }
      if (generation != _catalogPublishGeneration) return;
      await channel.invokeMethod<int>('commitLiveChannelsUpdate', {
        'updateId': updateId,
      });
      await _publishContentCatalogInChunks(generation, updateId);
    } on MissingPluginException {
      // Yerel TV sunucusu yalnızca Android/Fire TV derlemesinde bulunur.
    } on PlatformException catch (error) {
      debugPrint('Telefon kanal kataloğu yayınlanamadı: ${error.code}');
    }
  }

  Future<Map<String, int>> _recentLiveChannelOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, int>{};
    final profileIds = <String>{
      'default',
      if (_settings.lastProfileId != null) _settings.lastProfileId!,
      ..._settings.profiles.map((profile) => profile.id),
    };
    for (final profileId in profileIds) {
      final urls =
          prefs.getStringList('recentLiveChannelUrls_$profileId') ?? const [];
      for (var index = 0; index < urls.length; index++) {
        final currentOrder = result[urls[index]];
        if (currentOrder == null || index < currentOrder) {
          result[urls[index]] = index;
        }
      }
    }
    return result;
  }

  Future<void> _publishContentCatalogInChunks(
    int generation,
    String updateId,
  ) async {
    final nextMovies = <String, Channel>{};
    final nextSeries = <String, Channel>{};
    await channel.invokeMethod<void>('beginContentCatalogUpdate', {
      'updateId': updateId,
    });
    const chunkSize = 100;
    final items = _channels.movies
        .map((item) => (item, 'movie'))
        .followedBy(_channels.uniqueSeries.map((item) => (item, 'series')));
    var chunk = <Map<String, dynamic>>[];
    for (final (item, type) in items) {
      if (generation != _catalogPublishGeneration) return;
      if (_settings.isCategoryHidden(
        type,
        categoryLabel(item.category),
        profileId: item.sourceProfileId,
      )) {
        continue;
      }
      final id = channelRemoteId(item);
      if (type == 'movie') {
        nextMovies[id] = item;
      } else {
        nextSeries[id] = item;
      }
      chunk.add(_remoteContentMap(id, item, type));
      if (chunk.length < chunkSize) continue;
      await _appendContentChunk(updateId, chunk);
      chunk = <Map<String, dynamic>>[];
    }
    if (generation != _catalogPublishGeneration) return;
    if (chunk.isNotEmpty) await _appendContentChunk(updateId, chunk);
    await channel.invokeMethod<int>('commitContentCatalogUpdate', {
      'updateId': updateId,
    });
    _remoteMovies
      ..clear()
      ..addAll(nextMovies);
    _remoteSeries
      ..clear()
      ..addAll(nextSeries);
    _remoteEpisodes.clear();
  }

  Future<void> _appendContentChunk(
    String updateId,
    List<Map<String, dynamic>> contents,
  ) async {
    await channel.invokeMethod<void>('appendContentCatalogUpdate', {
      'updateId': updateId,
      'contents': contents,
    });
    await Future<void>.delayed(const Duration(milliseconds: 12));
  }

  Map<String, dynamic> _remoteContentMap(
    String id,
    Channel item,
    String type,
  ) {
    final profileId = item.sourceProfileId ?? _settings.lastProfileId ?? '';
    final historyId = type == 'series' ? 'series:${item.id}' : item.url;
    final lastWatchedAt = _history.getLastWatchedAt(
      historyId,
      profileId: profileId,
    );
    final now = DateTime.now().toUtc();
    final addedAt = item.addedAt;
    final isNewlyAdded = addedAt != null &&
        !addedAt.isBefore(now.subtract(const Duration(days: 7))) &&
        !addedAt.isAfter(now.add(const Duration(days: 1)));
    return {
      'id': id,
      'name': item.name,
      'category': categoryLabel(item.category),
      'profileName': item.sourceProfileName ?? '',
      'type': type,
      'isFavorite': _settings.isFavorite(
        type,
        item.id,
        profileId: item.sourceProfileId,
      ),
      'isRecentlyWatched': lastWatchedAt != null,
      'lastWatchedAt': lastWatchedAt?.toIso8601String(),
      'isNewlyAdded': isNewlyAdded,
    };
  }

  Future<List<Map<String, dynamic>>> _loadRemoteSeriesEpisodes(
    String seriesId,
  ) async {
    final series = _remoteSeries[seriesId];
    if (series == null) return const [];
    final episodes = await _channels.loadSeriesEpisodes(series);
    final result = <Map<String, dynamic>>[];
    for (var index = 0; index < episodes.length; index++) {
      final episode = episodes[index];
      final id = channelRemoteId(episode);
      _remoteEpisodes[id] = LocalEpisodeSelection(
        episode: episode,
        episodes: episodes,
        index: index,
        seriesName: series.name,
        seriesId: 'series:${series.id}',
      );
      result.add({
        'id': id,
        'name': episode.name,
        'profileName':
            episode.sourceProfileName ?? series.sourceProfileName ?? '',
      });
    }
    return result;
  }

  void _handleRemoteContentPlay(String id) {
    final movie = _remoteMovies[id];
    if (movie != null) {
      contentPlayRequest.value = LocalContentPlayRequest(
        item: movie,
        sequence: ++_playRequestSequence,
        section: LocalContentSection.movies,
      );
      return;
    }
    final episode = _remoteEpisodes[id];
    if (episode == null) return;
    contentPlayRequest.value = LocalContentPlayRequest(
      item: episode.episode,
      sequence: ++_playRequestSequence,
      section: LocalContentSection.series,
      playlist: episode.episodes,
      initialIndex: episode.index,
      seriesName: episode.seriesName,
      seriesId: episode.seriesId,
    );
  }

  void _showPairingPrompt(Map<String, dynamic> args) {
    final code = args['code']?.toString() ?? '';
    final expiresAtMs = (args['expiresAt'] as num?)?.toInt() ?? 0;
    if (!RegExp(r'^\d{6}$').hasMatch(code) || expiresAtMs <= 0) return;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    pairingPrompt.value = LocalPairingPrompt(code: code, expiresAt: expiresAt);
    _pairingPromptTimer?.cancel();
    final remaining = expiresAt.difference(DateTime.now());
    _pairingPromptTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _clearPairingPrompt,
    );
  }

  void _clearPairingPrompt() {
    _pairingPromptTimer?.cancel();
    _pairingPromptTimer = null;
    pairingPrompt.value = null;
  }

  Future<void> _saveReceivedProfile(
    String name,
    String playlistUrl, {
    String? profileId,
  }) async {
    final trimmedName = name.trim();
    final trimmedUrl = playlistUrl.trim();
    final uri = Uri.tryParse(trimmedUrl);
    if (trimmedName.isEmpty ||
        uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Invalid local companion profile');
    }
    final requestedId = profileId?.trim();
    final existing = requestedId?.isNotEmpty == true
        ? _settings.profiles
            .where((profile) => profile.id == requestedId)
            .firstOrNull
        : _settings.profiles
            .where((profile) => profile.m3uUrl == trimmedUrl)
            .firstOrNull;
    if (requestedId?.isNotEmpty == true && existing == null) {
      throw const FormatException('Unknown local companion profile');
    }
    final initials = trimmedName.length == 1
        ? trimmedName.toUpperCase()
        : trimmedName.substring(0, 2).toUpperCase();
    final profile = Profile(
      id: existing?.id ??
          'phone_${DateTime.now().microsecondsSinceEpoch.toString()}',
      name: trimmedName,
      initial: initials,
      m3uUrl: trimmedUrl,
      colorIndex: existing?.colorIndex ?? 0,
    );
    await _settings.saveProfile(profile);
    unawaited(_channels.loadProfiles(_settings.profiles));
    receivedProfile.value = profile;
    debugPrint('Telefon üzerinden profil güvenli şekilde kaydedildi.');
  }
}

class LocalPairingPrompt {
  const LocalPairingPrompt({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

class LocalChannelPlayRequest {
  const LocalChannelPlayRequest({required this.id, required this.sequence});

  final String id;
  final int sequence;
}

class LocalContentPlayRequest {
  const LocalContentPlayRequest({
    required this.item,
    required this.sequence,
    required this.section,
    this.playlist,
    this.initialIndex,
    this.seriesName,
    this.seriesId,
  });

  final Channel item;
  final int sequence;
  final LocalContentSection section;
  final List<Channel>? playlist;
  final int? initialIndex;
  final String? seriesName;
  final String? seriesId;
}

enum LocalContentSection { movies, series }

class LocalEpisodeSelection {
  const LocalEpisodeSelection({
    required this.episode,
    required this.episodes,
    required this.index,
    required this.seriesName,
    required this.seriesId,
  });

  final Channel episode;
  final List<Channel> episodes;
  final int index;
  final String seriesName;
  final String seriesId;
}
