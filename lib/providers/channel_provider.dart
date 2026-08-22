import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/profile.dart';
import '../services/playlist_service.dart';
import '../utils/scoped_category.dart';

class ChannelProvider with ChangeNotifier {
  static const int _playlistCacheVersion = 5;
  static const Duration _cacheReadTimeout = Duration(seconds: 8);

  final PlaylistService _playlistService = PlaylistService();
  List<Channel> _channels = [];
  bool _isLoading = false;
  String? _error;
  String? _warning;
  String? _activePlaylistUrl;
  int _loadGeneration = 0;
  final Map<String, List<Channel>> _seriesEpisodeCache = {};
  final Map<String, List<Channel>> _profileChannels = {};
  List<Channel>? _cachedLiveChannels;
  List<Channel>? _cachedMovies;
  List<Channel>? _cachedRawSeries;
  List<Channel>? _cachedUniqueSeries;
  Map<String, List<Channel>>? _cachedSeriesGroups;

  List<Channel> get channels => List.unmodifiable(_channels);
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get warning => _warning;
  String? get activePlaylistUrl => _activePlaylistUrl;

  List<Channel> get liveChannels {
    _ensureDerivedCatalogs();
    return _cachedLiveChannels!;
  }

  List<Channel> get movies {
    _ensureDerivedCatalogs();
    return _cachedMovies!;
  }

  List<Channel> get rawSeries {
    _ensureDerivedCatalogs();
    return _cachedRawSeries!;
  }

  Map<String, List<Channel>> get seriesGroups {
    _ensureDerivedCatalogs();
    return _cachedSeriesGroups!;
  }

  List<Channel> get uniqueSeries {
    _ensureDerivedCatalogs();
    return _cachedUniqueSeries!;
  }

  void _ensureDerivedCatalogs() {
    if (_cachedLiveChannels != null) return;
    final live = <Channel>[];
    final movies = <Channel>[];
    final rawSeries = <Channel>[];
    for (final channel in _channels) {
      if (channel.isLive) {
        live.add(channel);
      } else if (channel.isSeries || _isSeries(channel)) {
        rawSeries.add(channel);
      } else {
        movies.add(channel);
      }
    }

    final groups = <String, List<Channel>>{};
    for (final series in rawSeries.where((item) => item.seriesId == null)) {
      final baseName = _getSeriesBaseName(series.name);
      final groupKey = series.sourceProfileId == null
          ? baseName
          : scopeCategory(series.sourceProfileId!, baseName);
      groups.putIfAbsent(groupKey, () => []).add(series);
    }
    for (final list in groups.values) {
      list.sort(
        (a, b) => _episodeSortKey(a.name).compareTo(_episodeSortKey(b.name)),
      );
    }
    final catalogSeries = rawSeries
        .where((item) => item.seriesId != null)
        .toList();
    final groupedSeries = groups.entries
        .map((entry) {
          final firstEpisode = entry.value.first;
          return Channel(
            id: 'series_${firstEpisode.sourceProfileId ?? ''}_${entry.key}',
            name: categoryLabel(entry.key),
            url: firstEpisode.url,
            category: firstEpisode.category,
            logoUrl: firstEpisode.logoUrl,
            isLive: false,
            httpHeaders: firstEpisode.httpHeaders,
            addedAt: _latestAddedAt(entry.value),
            sourceProfileId: firstEpisode.sourceProfileId,
            sourceProfileName: firstEpisode.sourceProfileName,
            sourcePlaylistUrl: firstEpisode.sourcePlaylistUrl,
          );
        })
        .toList(growable: false);

    _cachedLiveChannels = List<Channel>.unmodifiable(live);
    _cachedMovies = List<Channel>.unmodifiable(movies);
    _cachedRawSeries = List<Channel>.unmodifiable(rawSeries);
    _cachedSeriesGroups = Map<String, List<Channel>>.unmodifiable(
      groups.map(
        (key, value) =>
            MapEntry(key, List<Channel>.unmodifiable(value)),
      ),
    );
    _cachedUniqueSeries = List<Channel>.unmodifiable([
      ...catalogSeries,
      ...groupedSeries,
    ]);
  }

  void _invalidateDerivedCatalogs() {
    _cachedLiveChannels = null;
    _cachedMovies = null;
    _cachedRawSeries = null;
    _cachedUniqueSeries = null;
    _cachedSeriesGroups = null;
  }

  DateTime? _latestAddedAt(List<Channel> channels) {
    DateTime? latest;
    for (final channel in channels) {
      final date = channel.addedAt;
      if (date != null && (latest == null || date.isAfter(latest))) {
        latest = date;
      }
    }
    return latest;
  }

  Future<List<Channel>> loadSeriesEpisodes(Channel series) async {
    final seriesId = series.seriesId;
    if (seriesId == null) {
      final key = series.sourceProfileId == null
          ? series.name
          : scopeCategory(series.sourceProfileId!, series.name);
      return seriesGroups[key] ?? const [];
    }
    final cacheKey = '${series.sourceProfileId ?? ''}:$seriesId';
    final cached = _seriesEpisodeCache[cacheKey];
    if (cached != null) return cached;
    final playlistUrl = series.sourcePlaylistUrl ?? _activePlaylistUrl;
    if (playlistUrl == null) return const [];
    final fetched = await _playlistService.fetchSeriesEpisodes(
      playlistUrl,
      seriesId,
    );
    final episodes = fetched
        .map(
          (episode) => _attachSource(
            episode,
            profileId: series.sourceProfileId,
            profileName: series.sourceProfileName,
            playlistUrl: playlistUrl,
          ),
        )
        .toList(growable: false);
    _seriesEpisodeCache[cacheKey] = episodes;
    return episodes;
  }

  Future<void> loadProfiles(List<Profile> profiles) async {
    final usable = profiles
        .where((profile) => profile.m3uUrl?.trim().isNotEmpty == true)
        .toList(growable: false);
    if (usable.isEmpty) {
      clearChannels();
      _error = 'Oynatma listesi adresi boş olamaz.';
      notifyListeners();
      return;
    }

    final generation = ++_loadGeneration;
    _isLoading = true;
    _error = null;
    _warning = null;
    notifyListeners();

    final results = await Future.wait(
      usable.map((profile) => _loadProfileInitial(profile, generation)),
    );
    if (generation != _loadGeneration) return;
    _profileChannels
      ..clear()
      ..addEntries(results.where((entry) => entry.value.isNotEmpty));
    _rebuildMergedChannels();
    _activePlaylistUrl = usable.first.m3uUrl!.trim();
    _isLoading = false;
    if (_channels.isEmpty) {
      _error = 'Hiçbir kullanıcı listesi yüklenemedi.';
    } else if (results.any((entry) => entry.value.isEmpty)) {
      _warning = 'Bazı kullanıcı listeleri yüklenemedi.';
    }
    notifyListeners();
  }

  Future<MapEntry<String, List<Channel>>> _loadProfileInitial(
    Profile profile,
    int generation,
  ) async {
    final url = profile.m3uUrl!.trim();
    final cacheFile = await _getCacheFile(url);
    var channels = await _readCache(
      cacheFile,
    ).timeout(_cacheReadTimeout, onTimeout: () => const <Channel>[]);
    if (channels.isEmpty) {
      try {
        channels = await _playlistService.fetchPlaylist(url);
        final encoded = await compute(_encodeChannels, channels);
        await _writeCacheAtomically(cacheFile, encoded);
      } catch (error) {
        debugPrint('${profile.name} listesi yüklenemedi: ${error.runtimeType}');
        return MapEntry(profile.id, const []);
      }
    } else {
      unawaited(_refreshProfileInBackground(profile, cacheFile, generation));
    }
    final tracked = await _applyCatalogTracking(channels, url, profile.id);
    return MapEntry(
      profile.id,
      tracked
          .map(
            (channel) => _attachSource(
              channel,
              profileId: profile.id,
              profileName: profile.name,
              playlistUrl: url,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> _refreshProfileInBackground(
    Profile profile,
    File cacheFile,
    int generation,
  ) async {
    final url = profile.m3uUrl!.trim();
    try {
      final fetched = await _playlistService.fetchPlaylist(url);
      final tracked = await _applyCatalogTracking(fetched, url, profile.id);
      if (generation != _loadGeneration) return;
      _profileChannels[profile.id] = tracked
          .map(
            (channel) => _attachSource(
              channel,
              profileId: profile.id,
              profileName: profile.name,
              playlistUrl: url,
            ),
          )
          .toList(growable: false);
      _rebuildMergedChannels();
      notifyListeners();
      final encoded = await compute(_encodeChannels, fetched);
      await _writeCacheAtomically(cacheFile, encoded);
    } catch (error) {
      debugPrint(
        '${profile.name} ağ yenilemesi başarısız: ${error.runtimeType}',
      );
    }
  }

  Channel _attachSource(
    Channel channel, {
    required String? profileId,
    required String? profileName,
    required String playlistUrl,
  }) {
    if (profileId == null || profileId.isEmpty) return channel;
    return channel.copyWith(
      category: scopeCategory(profileId, categoryLabel(channel.category)),
      sourceProfileId: profileId,
      sourceProfileName: profileName,
      sourcePlaylistUrl: playlistUrl,
    );
  }

  void _rebuildMergedChannels() {
    _channels = _profileChannels.values.expand((items) => items).toList();
    _invalidateDerivedCatalogs();
    _seriesEpisodeCache.clear();
  }

  bool _isSeries(Channel channel) {
    if (channel.isLive) return false;

    final name = channel.name.toLowerCase();
    final category = channel.category.toLowerCase();
    final isMovieCategory =
        category.contains('film') ||
        category.contains('movie') ||
        category.contains('sinema') ||
        category.contains('aksiyon') ||
        category.contains('bilim kurgu');
    final isSeriesCategory =
        category.contains('series') ||
        category.contains('dizi') ||
        category.contains('sezon') ||
        category.contains('season') ||
        category.contains('show');

    if (isMovieCategory && !isSeriesCategory) return false;
    if (isSeriesCategory) return true;

    return <RegExp>[
      RegExp(r'S\d+\s*E\d+', caseSensitive: false),
      RegExp(r'\d+x\d+', caseSensitive: false),
      RegExp(r'Season\s+\d+', caseSensitive: false),
      RegExp(r'Sezon\s+\d+', caseSensitive: false),
      RegExp(r'Bölüm\s+\d+', caseSensitive: false),
      RegExp(r'Episode\s+\d+', caseSensitive: false),
    ].any((pattern) => pattern.hasMatch(name));
  }

  String _getSeriesBaseName(String fullName) {
    final match = RegExp(
      r'(.*?)(?=S\d+\s*E\d+|\d+x\d+|Season\s+\d+|Sezon\s+\d+|Bölüm\s+\d+|Episode\s+\d+|-?\s*E\d+)',
      caseSensitive: false,
    ).firstMatch(fullName);
    final baseName = match?.group(1)?.trim();
    if (baseName == null || baseName.isEmpty) return fullName.trim();
    return baseName.replaceAll(RegExp(r'\s*[-–:]$'), '').trim();
  }

  int _episodeSortKey(String name) {
    final seasonEpisode = RegExp(
      r'S(\d+)\s*E(\d+)',
      caseSensitive: false,
    ).firstMatch(name);
    if (seasonEpisode != null) {
      return (int.tryParse(seasonEpisode.group(1)!) ?? 0) * 10000 +
          (int.tryParse(seasonEpisode.group(2)!) ?? 0);
    }
    final alternate = RegExp(
      r'(\d+)x(\d+)',
      caseSensitive: false,
    ).firstMatch(name);
    if (alternate != null) {
      return (int.tryParse(alternate.group(1)!) ?? 0) * 10000 +
          (int.tryParse(alternate.group(2)!) ?? 0);
    }
    return 1 << 30;
  }

  Future<File> _getCacheFile(String url) async {
    final directory = await getApplicationSupportDirectory();
    final fingerprint = _stableFingerprint(url);
    return File(
      '${directory.path}/playlist_v${_playlistCacheVersion}_$fingerprint.json',
    );
  }

  Future<void> loadPlaylist(String url, {String? profileId}) async {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      _channels = [];
      _invalidateDerivedCatalogs();
      _activePlaylistUrl = null;
      _error = 'Oynatma listesi adresi boş olamaz.';
      _warning = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    final generation = ++_loadGeneration;
    final isDifferentPlaylist = _activePlaylistUrl != normalizedUrl;
    _activePlaylistUrl = normalizedUrl;
    _error = null;
    _warning = null;
    _isLoading = true;
    if (isDifferentPlaylist) {
      // Bir profil yüklenirken başka profile ait içeriğin görünmesini önler.
      _channels = [];
      _invalidateDerivedCatalogs();
      _seriesEpisodeCache.clear();
    }
    notifyListeners();

    final cacheFile = await _getCacheFile(normalizedUrl);
    final cachedChannels = await _readCache(cacheFile).timeout(
      _cacheReadTimeout,
      onTimeout: () {
        debugPrint('Playlist cache okuma zaman aşımı; ağdan yenileniyor.');
        return const <Channel>[];
      },
    );
    if (generation != _loadGeneration) return;

    if (cachedChannels.isNotEmpty) {
      final trackedChannels = await _applyCatalogTracking(
        cachedChannels,
        normalizedUrl,
        profileId,
      );
      if (generation != _loadGeneration ||
          _activePlaylistUrl != normalizedUrl) {
        return;
      }
      _channels = trackedChannels;
      _invalidateDerivedCatalogs();
      _isLoading = false;
      notifyListeners();

      // Cache ilk ekranı hemen açar; ağ yenilemesi sonucu daha sonra atomik
      // olarak uygulanır. Eski veya başka profile ait veri hiçbir zaman kalmaz.
      unawaited(
        _refreshFromNetwork(
          normalizedUrl,
          cacheFile,
          generation,
          profileId: profileId,
          hasUsableCache: true,
        ),
      );
      return;
    }

    await _refreshFromNetwork(
      normalizedUrl,
      cacheFile,
      generation,
      profileId: profileId,
      hasUsableCache: false,
    );
  }

  Future<List<Channel>> _readCache(File cacheFile) async {
    if (!await cacheFile.exists()) return const [];
    try {
      final jsonString = await cacheFile.readAsString();
      return compute(_decodeChannels, jsonString);
    } catch (error) {
      debugPrint('Playlist cache okunamadı: ${error.runtimeType}');
      return const [];
    }
  }

  Future<void> _refreshFromNetwork(
    String url,
    File cacheFile,
    int generation, {
    required String? profileId,
    required bool hasUsableCache,
  }) async {
    try {
      final networkChannels = await _playlistService.fetchPlaylist(url);
      if (generation != _loadGeneration || _activePlaylistUrl != url) return;

      final trackedChannels = await _applyCatalogTracking(
        networkChannels,
        url,
        profileId,
      );
      if (generation != _loadGeneration || _activePlaylistUrl != url) return;
      _channels = trackedChannels;
      _invalidateDerivedCatalogs();
      _error = null;
      _warning = null;
      _isLoading = false;
      notifyListeners();

      try {
        final jsonString = await compute(_encodeChannels, networkChannels);
        await _writeCacheAtomically(cacheFile, jsonString);
      } catch (error) {
        debugPrint('Playlist cache yazılamadı: ${error.runtimeType}');
      }
    } catch (error) {
      if (generation != _loadGeneration || _activePlaylistUrl != url) return;
      _isLoading = false;
      if (hasUsableCache) {
        _warning = 'Ağ yenilemesi başarısız; kayıtlı liste kullanılıyor.';
      } else {
        _channels = [];
        _invalidateDerivedCatalogs();
        _error = error.toString();
      }
      notifyListeners();
    }
  }

  Future<List<Channel>> _applyCatalogTracking(
    List<Channel> channels,
    String playlistUrl,
    String? profileId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final playlistScope = _stableFingerprint(playlistUrl);
    final profileScope = profileId?.trim().isNotEmpty == true
        ? profileId!.trim()
        : 'anonymous';
    final scope = '$profileScope|$playlistScope';
    final storageKey = 'catalog_first_seen_v1_${_stableFingerprint(scope)}';
    final stored = prefs.getString(storageKey);
    final seen = <String, int>{};
    if (stored != null) {
      try {
        final decoded = jsonDecode(stored);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is int) seen[entry.key.toString()] = value;
          }
        }
      } catch (_) {}
    }

    final isBaseline = stored == null;
    final now = DateTime.now().toUtc();
    final tracked = <Channel>[];
    for (final channel in channels) {
      final identity = _catalogIdentity(channel);
      final previous = seen[identity];
      DateTime? effectiveAddedAt = channel.addedAt;

      if (effectiveAddedAt != null) {
        seen[identity] = effectiveAddedAt.millisecondsSinceEpoch;
      } else if (previous != null && previous > 0) {
        effectiveAddedAt = DateTime.fromMillisecondsSinceEpoch(
          previous,
          isUtc: true,
        );
      } else if (!isBaseline && previous == null) {
        effectiveAddedAt = now;
        seen[identity] = now.millisecondsSinceEpoch;
      } else {
        // Zero is a baseline tombstone. If the item disappears temporarily and
        // returns, it is not incorrectly treated as newly added.
        seen.putIfAbsent(identity, () => 0);
      }

      tracked.add(channel.copyWith(addedAt: effectiveAddedAt));
    }
    await prefs.setString(storageKey, jsonEncode(seen));
    return tracked;
  }

  String _catalogIdentity(Channel channel) {
    final type = channel.isLive
        ? 'live'
        : channel.seriesId != null || channel.isSeries
        ? 'series'
        : 'vod';
    final stableId = channel.id.trim().isNotEmpty
        ? channel.id.trim()
        : _stableFingerprint(channel.url);
    return '$type|$stableId';
  }

  Future<void> _writeCacheAtomically(File cacheFile, String contents) async {
    final temporaryFile = File('${cacheFile.path}.tmp');
    await temporaryFile.writeAsString(contents, flush: true);
    try {
      await temporaryFile.rename(cacheFile.path);
    } on FileSystemException {
      if (await cacheFile.exists()) await cacheFile.delete();
      await temporaryFile.rename(cacheFile.path);
    }
  }

  void clearChannels() {
    _loadGeneration++;
    _activePlaylistUrl = null;
    _channels = [];
    _invalidateDerivedCatalogs();
    _profileChannels.clear();
    _seriesEpisodeCache.clear();
    _error = null;
    _warning = null;
    _isLoading = false;
    notifyListeners();
  }
}

List<Channel> _decodeChannels(String jsonString) {
  final decoded = jsonDecode(jsonString);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((item) => Channel.fromMap(Map<String, dynamic>.from(item)))
      .where((channel) => channel.url.isNotEmpty && channel.name.isNotEmpty)
      .toList();
}

String _encodeChannels(List<Channel> channels) {
  return jsonEncode(channels.map((channel) => channel.toMap()).toList());
}

String _stableFingerprint(String value) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(value)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
