import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/channel.dart';

class PlaylistService {
  Future<List<Channel>> fetchPlaylist(
    String url, {
    bool isFallback = false,
  }) async {
    final uri = _normalizePlaylistUri(url);

    final xtream = _XtreamConnection.tryParse(uri);
    if (xtream != null && !isFallback) {
      try {
        final catalog = await _fetchXtreamCatalog(xtream);
        if (catalog.isNotEmpty) return catalog;
      } catch (error) {
        debugPrint(
          'Xtream katalogu alınamadı; M3U yedeği deneniyor: '
          '${error.runtimeType}',
        );
      }
    }

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'IPTVSmartersPlayer',
          'Accept': '*/*',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        var channels = await compute(parseM3UContent, body);
        final responseCookies = _parseResponseCookies(
          response.headersSplitValues['set-cookie'] ?? const [],
          uri.host,
        );
        if (responseCookies.isNotEmpty) {
          channels = channels
              .map(
                (channel) => _attachApplicableCookies(channel, responseCookies),
              )
              .toList(growable: false);
        }
        if (channels.isEmpty) {
          throw const FormatException(
            'Oynatma listesinde geçerli içerik bulunamadı.',
          );
        }
        return channels;
      }

      if (response.statusCode == 404 && !isFallback) {
        final fallbackUri = _buildXtreamFallback(uri);
        if (fallbackUri != null) {
          debugPrint(
            'Xtream playlist yolu bulunamadı; get.php biçimi deneniyor.',
          );
          return fetchPlaylist(fallbackUri.toString(), isFallback: true);
        }
      }

      throw HttpException('Sunucu hatası: ${response.statusCode}');
    } on FormatException {
      rethrow;
    } catch (error) {
      // HTTPS hiçbir koşulda kendiliğinden HTTP'ye düşürülmez. Kullanıcı açıkça
      // HTTP adresi verdiyse Android ağ güvenliği yapılandırması bunu destekler.
      final errorText = error.toString().toLowerCase();
      if (errorText.contains('failed host lookup') ||
          errorText.contains('socketexception')) {
        throw const HttpException(
          'Sunucuya ulaşılamıyor. İnternetinizi veya bağlantı adresini kontrol edin.',
        );
      }
      if (errorText.contains('timeout')) {
        throw const HttpException(
          'Sunucu zaman aşımına uğradı. Lütfen tekrar deneyin.',
        );
      }
      rethrow;
    }
  }

  List<Channel> parseM3U(String content) => parseM3UContent(content);

  Future<List<Channel>> fetchSeriesEpisodes(
    String playlistUrl,
    String seriesId,
  ) async {
    final connection = _XtreamConnection.tryParse(
      _normalizePlaylistUri(playlistUrl),
    );
    if (connection == null) return const [];
    final payload = await _getXtreamJson(
      connection.apiUri(action: 'get_series_info', seriesId: seriesId),
    );
    if (payload is! Map) return const [];

    final info = payload['info'] is Map ? payload['info'] as Map : const {};
    final seriesName =
        (info['name'] ?? info['title'] ?? 'Dizi').toString().trim();
    final episodes = payload['episodes'];
    if (episodes is! Map) return const [];

    final result = <Channel>[];
    for (final seasonEntry in episodes.entries) {
      final seasonNumber = int.tryParse(seasonEntry.key.toString()) ?? 0;
      final seasonEpisodes = seasonEntry.value;
      if (seasonEpisodes is! List) continue;
      for (final rawEpisode in seasonEpisodes.whereType<Map>()) {
        final episodeId = rawEpisode['id']?.toString() ?? '';
        if (episodeId.isEmpty) continue;
        final episodeNumber =
            int.tryParse(rawEpisode['episode_num']?.toString() ?? '') ?? 0;
        final title =
            (rawEpisode['title'] ?? rawEpisode['name'] ?? '').toString().trim();
        final extension = _safeExtension(
          rawEpisode['container_extension'],
          'mp4',
        );
        final directSource = rawEpisode['direct_source']?.toString().trim();
        final episodeInfo =
            rawEpisode['info'] is Map ? rawEpisode['info'] as Map : const {};
        final displayName = [
          seriesName,
          if (seasonNumber > 0 && episodeNumber > 0)
            'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}',
          if (title.isNotEmpty && title != seriesName) title,
        ].join(' - ');
        result.add(
          Channel(
            id: 'xtream_episode_$episodeId',
            name: displayName,
            url: _usableDirectSource(directSource) ??
                connection.streamUri('series', episodeId, extension),
            category: seriesName,
            logoUrl: (episodeInfo['movie_image'] ?? info['cover'])?.toString(),
            isLive: false,
            isSeries: true,
          ),
        );
      }
    }
    return result;
  }

  Future<List<Channel>> _fetchXtreamCatalog(
    _XtreamConnection connection,
  ) async {
    final results = await Future.wait([
      _getXtreamList(connection.apiUri(action: 'get_live_categories')),
      _getXtreamList(connection.apiUri(action: 'get_live_streams')),
      _getXtreamList(connection.apiUri(action: 'get_vod_categories')),
      _getXtreamList(connection.apiUri(action: 'get_vod_streams')),
      _getXtreamList(connection.apiUri(action: 'get_series_categories')),
      _getXtreamList(connection.apiUri(action: 'get_series')),
    ]);
    final liveCategories = _categoryMap(results[0]);
    final liveStreams = results[1];
    final vodCategories = _categoryMap(results[2]);
    final vodStreams = results[3];
    final seriesCategories = _categoryMap(results[4]);
    final series = results[5];

    debugPrint(
      'Xtream katalog sayıları: canlı=${liveStreams.length}, '
      'film=${vodStreams.length}, dizi=${series.length}',
    );

    final channels = <Channel>[];
    for (final item in liveStreams.whereType<Map>()) {
      final streamId = item['stream_id']?.toString() ?? '';
      final name = item['name']?.toString().trim() ?? '';
      if (streamId.isEmpty || name.isEmpty) continue;
      final extension = _safeExtension(item['container_extension'], 'ts');
      channels.add(
        Channel(
          id: 'xtream_live_$streamId',
          name: name,
          url: _usableDirectSource(item['direct_source']?.toString()) ??
              connection.streamUri('live', streamId, extension),
          category: liveCategories[item['category_id']?.toString()] ?? 'Genel',
          logoUrl: _nullableText(item['stream_icon']),
          tvgId: _nullableText(item['epg_channel_id']),
          isLive: true,
        ),
      );
    }
    for (final item in vodStreams.whereType<Map>()) {
      final streamId = item['stream_id']?.toString() ?? '';
      final name = item['name']?.toString().trim() ?? '';
      if (streamId.isEmpty || name.isEmpty) continue;
      final extension = _safeExtension(item['container_extension'], 'mp4');
      channels.add(
        Channel(
          id: 'xtream_vod_$streamId',
          name: name,
          url: _usableDirectSource(item['direct_source']?.toString()) ??
              connection.streamUri('movie', streamId, extension),
          category: vodCategories[item['category_id']?.toString()] ?? 'Genel',
          logoUrl: _nullableText(item['stream_icon']),
          addedAt: _parseProviderDate(
            item['added'] ?? item['date_added'] ?? item['created_at'],
          ),
          isLive: false,
        ),
      );
    }
    for (final item in series.whereType<Map>()) {
      final seriesId = item['series_id']?.toString() ?? '';
      final name = item['name']?.toString().trim() ?? '';
      if (seriesId.isEmpty || name.isEmpty) continue;
      channels.add(
        Channel(
          id: 'xtream_series_$seriesId',
          name: name,
          url: 'xtream-series:$seriesId',
          category:
              seriesCategories[item['category_id']?.toString()] ?? 'Genel',
          logoUrl: _nullableText(item['cover'] ?? item['stream_icon']),
          addedAt: _parseProviderDate(
            item['added'] ?? item['date_added'] ?? item['created_at'],
          ),
          isLive: false,
          isSeries: true,
          seriesId: seriesId,
        ),
      );
    }
    return channels;
  }
}

class _XtreamConnection {
  final Uri source;
  final String username;
  final String password;

  const _XtreamConnection(this.source, this.username, this.password);

  static _XtreamConnection? tryParse(Uri uri) {
    var username = uri.queryParameters['username']?.trim() ?? '';
    var password = uri.queryParameters['password']?.trim() ?? '';
    final segments = uri.pathSegments;
    final playlistIndex = segments.indexOf('playlist');
    if ((username.isEmpty || password.isEmpty) &&
        playlistIndex >= 0 &&
        segments.length > playlistIndex + 2) {
      username = segments[playlistIndex + 1].trim();
      password = segments[playlistIndex + 2].trim();
    }
    if (username.isEmpty || password.isEmpty) return null;
    return _XtreamConnection(uri, username, password);
  }

  Uri apiUri({required String action, String? seriesId}) {
    return source.replace(
      path: '/player_api.php',
      queryParameters: {
        'username': username,
        'password': password,
        'action': action,
        if (seriesId != null) 'series_id': seriesId,
      },
      fragment: '',
    );
  }

  String streamUri(String type, String id, String extension) {
    return Uri(
      scheme: source.scheme,
      host: source.host,
      port: source.hasPort ? source.port : null,
      pathSegments: [type, username, password, '$id.$extension'],
    ).toString();
  }
}

Future<dynamic> _getXtreamJson(Uri uri) async {
  final response = await http.get(
    uri,
    headers: const {'User-Agent': 'IPTVSmartersPlayer', 'Accept': '*/*'},
  ).timeout(const Duration(seconds: 30));
  if (response.statusCode != 200) {
    throw HttpException('Xtream sunucu hatası: ${response.statusCode}');
  }
  return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
}

Future<List<dynamic>> _getXtreamList(Uri uri) async {
  final decoded = await _getXtreamJson(uri);
  return decoded is List ? decoded : const [];
}

Map<String, String> _categoryMap(List<dynamic> categories) {
  return {
    for (final category in categories.whereType<Map>())
      if (category['category_id'] != null)
        category['category_id'].toString():
            (category['category_name'] ?? 'Genel').toString(),
  };
}

String _safeExtension(dynamic value, String fallback) {
  final extension = value?.toString().trim().toLowerCase() ?? '';
  return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension) ? extension : fallback;
}

String? _usableDirectSource(String? value) {
  final source = value?.trim() ?? '';
  final uri = Uri.tryParse(source);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return source;
}

String? _nullableText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _parseProviderDate(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == '0') return null;

  final numeric = int.tryParse(text);
  DateTime? parsed;
  if (numeric != null) {
    final milliseconds = numeric.abs() >= 100000000000
        ? numeric
        : numeric * Duration.millisecondsPerSecond;
    parsed = DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  } else {
    parsed = DateTime.tryParse(text)?.toUtc();
  }
  if (parsed == null || parsed.year < 2000 || parsed.year > 2200) return null;
  return parsed;
}

class _ScopedCookie {
  final String pair;
  final String domain;

  const _ScopedCookie(this.pair, this.domain);
}

List<_ScopedCookie> _parseResponseCookies(
  List<String> setCookieValues,
  String responseHost,
) {
  final cookies = <_ScopedCookie>[];
  for (final value in setCookieValues) {
    final parts = value.split(';');
    final pair = parts.first.trim();
    if (!pair.contains('=') || pair.startsWith('=')) continue;
    var domain = responseHost.toLowerCase();
    for (final attribute in parts.skip(1)) {
      final trimmed = attribute.trim();
      if (trimmed.toLowerCase().startsWith('domain=')) {
        domain = trimmed.substring(7).trim().toLowerCase();
        if (domain.startsWith('.')) domain = domain.substring(1);
      }
    }
    if (domain.isNotEmpty) cookies.add(_ScopedCookie(pair, domain));
  }
  return cookies;
}

Channel _attachApplicableCookies(Channel channel, List<_ScopedCookie> cookies) {
  final streamHost = Uri.tryParse(channel.url)?.host.toLowerCase() ?? '';
  if (streamHost.isEmpty) return channel;
  final applicable = cookies
      .where(
        (cookie) =>
            streamHost == cookie.domain ||
            streamHost.endsWith('.${cookie.domain}'),
      )
      .map((cookie) => cookie.pair)
      .toList(growable: false);
  if (applicable.isEmpty) return channel;

  final headers = Map<String, String>.from(channel.httpHeaders);
  final existingCookie = headers['Cookie'];
  headers['Cookie'] = [
    if (existingCookie != null && existingCookie.isNotEmpty) existingCookie,
    ...applicable,
  ].join('; ');
  return Channel(
    id: channel.id,
    name: channel.name,
    url: channel.url,
    category: channel.category,
    logoUrl: channel.logoUrl,
    tvgId: channel.tvgId,
    isLive: channel.isLive,
    isSeries: channel.isSeries,
    seriesId: channel.seriesId,
    httpHeaders: Map.unmodifiable(headers),
  );
}

class HttpException implements Exception {
  final String message;

  const HttpException(this.message);

  @override
  String toString() => message;
}

Uri _normalizePlaylistUri(String rawUrl) {
  final value = rawUrl.trim();
  if (value.isEmpty) {
    throw const FormatException('Oynatma listesi adresi boş olamaz.');
  }

  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw const FormatException(
      'Geçerli bir http:// veya https:// oynatma listesi adresi girin.',
    );
  }
  return uri;
}

Uri? _buildXtreamFallback(Uri uri) {
  final segments = uri.pathSegments;
  final playlistIndex = segments.indexOf('playlist');
  if (playlistIndex < 0 || segments.length <= playlistIndex + 3) {
    return null;
  }
  if (segments[playlistIndex + 3] != 'm3u_plus') {
    return null;
  }

  return uri.replace(
    path: '/get.php',
    queryParameters: {
      'username': segments[playlistIndex + 1],
      'password': segments[playlistIndex + 2],
      'type': 'm3u_plus',
      'output': 'm3u8',
    },
  );
}

List<Channel> parseM3UContent(String content) {
  final channels = <Channel>[];
  final lines = content.split(RegExp(r'\r?\n'));

  String? currentName;
  String? currentLogo;
  String? currentGroup;
  String? currentTvgId;
  DateTime? currentAddedAt;
  var currentHeaders = <String, String>{};

  for (final line in lines) {
    final trimmedLine = line.trim();
    if (trimmedLine.isEmpty) continue;

    if (trimmedLine.startsWith('#EXTINF:')) {
      currentHeaders = <String, String>{};
      currentGroup = _extractAttribute(trimmedLine, 'group-title');
      currentLogo = _extractAttribute(trimmedLine, 'tvg-logo');
      currentTvgId = _extractAttribute(trimmedLine, 'tvg-id');
      currentAddedAt = _parseProviderDate(
        _extractAttribute(trimmedLine, 'added') ??
            _extractAttribute(trimmedLine, 'date-added') ??
            _extractAttribute(trimmedLine, 'tvg-added'),
      );

      final commaIndex = trimmedLine.lastIndexOf(',');
      currentName = commaIndex >= 0
          ? trimmedLine.substring(commaIndex + 1).trim()
          : _extractAttribute(trimmedLine, 'tvg-name') ?? 'Bilinmeyen Kanal';
    } else if (trimmedLine.startsWith('#EXTGRP:')) {
      currentGroup = trimmedLine.substring(8).trim();
    } else if (trimmedLine.startsWith('#EXTVLCOPT:')) {
      _parseVlcOption(trimmedLine.substring(11), currentHeaders);
    } else if (trimmedLine.startsWith('#EXTHTTP:')) {
      _parseExtHttp(trimmedLine.substring(9), currentHeaders);
    } else if (!trimmedLine.startsWith('#') && currentName != null) {
      final parsedStream = _parseStreamUrl(trimmedLine);
      final streamUrl = parsedStream.$1;
      currentHeaders.addAll(parsedStream.$2);
      final category = currentGroup?.trim().isNotEmpty == true
          ? currentGroup!.trim()
          : 'Genel';
      final id = currentTvgId?.trim().isNotEmpty == true
          ? currentTvgId!.trim()
          : 'channel_${_stableHash('$currentName|$streamUrl|$category')}';

      channels.add(
        Channel(
          id: id,
          name: currentName,
          url: streamUrl,
          category: category,
          logoUrl: currentLogo,
          tvgId: currentTvgId,
          addedAt: currentAddedAt,
          isLive: _checkIfLive(streamUrl, currentGroup, currentName),
          httpHeaders: Map.unmodifiable(currentHeaders),
        ),
      );

      currentName = null;
      currentLogo = null;
      currentGroup = null;
      currentTvgId = null;
      currentAddedAt = null;
      currentHeaders = <String, String>{};
    }
  }
  return channels;
}

void _parseVlcOption(String option, Map<String, String> headers) {
  final separator = option.indexOf('=');
  if (separator <= 0) return;
  final key = option.substring(0, separator).trim().toLowerCase();
  final value = option.substring(separator + 1).trim();
  if (value.isEmpty) return;
  switch (key) {
    case 'http-user-agent':
      headers['User-Agent'] = value;
    case 'http-referrer':
    case 'http-referer':
      headers['Referer'] = value;
    case 'http-origin':
      headers['Origin'] = value;
    case 'http-cookie':
      headers['Cookie'] = value;
  }
}

void _parseExtHttp(String value, Map<String, String> headers) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        final name = entry.key.toString().trim();
        final headerValue = entry.value?.toString().trim() ?? '';
        if (name.isNotEmpty && headerValue.isNotEmpty) {
          headers[name] = headerValue;
        }
      }
    }
  } catch (_) {}
}

(String, Map<String, String>) _parseStreamUrl(String value) {
  final separator = value.indexOf('|');
  if (separator < 0) return (value, const {});
  final url = value.substring(0, separator).trim();
  final headers = <String, String>{};
  for (final part in value.substring(separator + 1).split('&')) {
    final equals = part.indexOf('=');
    if (equals <= 0) continue;
    final rawName = Uri.decodeComponent(part.substring(0, equals)).trim();
    final headerValue = Uri.decodeComponent(part.substring(equals + 1)).trim();
    if (rawName.isEmpty || headerValue.isEmpty) continue;
    final lower = rawName.toLowerCase();
    final name = switch (lower) {
      'user-agent' || 'http-user-agent' => 'User-Agent',
      'referer' || 'referrer' || 'http-referrer' => 'Referer',
      'origin' || 'http-origin' => 'Origin',
      'cookie' || 'http-cookie' => 'Cookie',
      _ => rawName,
    };
    headers[name] = headerValue;
  }
  return (url, headers);
}

String? _extractAttribute(String line, String attribute) {
  final regex = RegExp(
    '$attribute=["\']?([^"\',]*)["\']?',
    caseSensitive: false,
  );
  return regex.firstMatch(line)?.group(1)?.trim();
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(value)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

bool _checkIfLive(String url, String? group, String name) {
  final lowerUrl = url.toLowerCase();
  final lowerGroup = group?.toLowerCase() ?? '';
  final lowerName = name.toLowerCase();

  if (lowerUrl.contains('/live/')) return true;
  if (lowerUrl.contains('/movie/') ||
      lowerUrl.contains('/series/') ||
      lowerUrl.contains('type=vod') ||
      lowerUrl.contains('type=series')) {
    return false;
  }

  final path = Uri.tryParse(lowerUrl)?.path ?? lowerUrl;
  const vodExtensions = <String>{
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.flv',
    '.mpg',
    '.mpeg',
  };
  if (vodExtensions.any(path.endsWith)) return false;

  const channelKeywords = <String>[
    'kanal',
    'canli',
    'canlı',
    'live',
    'ulusal',
    'spor',
    'haber',
    'yayin',
    'yayın',
    'bein',
    'exxen',
    'digiturk',
    'd-smart',
    'tivibu',
  ];
  if (channelKeywords.any(lowerGroup.contains)) return true;

  final combinedLabel = '$lowerGroup $lowerName';
  final isAroundTheClock = RegExp(
    r'(^|\D)(7\s*[/\\-]\s*24|24\s*[/\\-]\s*7|24\s*saat)(\D|$)',
    caseSensitive: false,
  ).hasMatch(combinedLabel);
  final isNamedChannel = RegExp(
    r'(^|\W)(tv|kanal|channel)(\W|$)',
    caseSensitive: false,
  ).hasMatch(combinedLabel);
  if (isAroundTheClock || isNamedChannel) return true;

  const seriesKeywords = <String>[
    'dizi',
    'series',
    'sezon',
    'season',
    'episode',
    'bölüm',
  ];
  if (seriesKeywords.any(lowerGroup.contains)) return false;

  const vodKeywords = <String>[
    'vod',
    'film',
    'movie',
    'netflix',
    'disney',
    'amazon',
  ];
  if (vodKeywords.any(lowerGroup.contains)) return false;

  // Sinema/Cinema tek başına belirsizdir. 7/24 ve TV/Kanal işaretleri
  // yukarıda canlı olarak ayrıldı; kalan sinema grupları VOD kabul edilir.
  if (lowerGroup.contains('sinema') || lowerGroup.contains('cinema')) {
    return false;
  }

  if (lowerUrl.contains('.m3u8') ||
      lowerUrl.contains('.ts') ||
      lowerUrl.contains('/play/')) {
    return true;
  }

  return !RegExp(
    r'S\d+\s*E\d+|\d+x\d+|Bölüm\s+\d+|Episode\s+\d+|Season\s+\d+|Sezon\s+\d+',
    caseSensitive: false,
  ).hasMatch(lowerName);
}
