import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';

class CurrentEpgProgram {
  const CurrentEpgProgram({required this.title, this.endsAt});
  final String title;
  final DateTime? endsAt;
}

class EpgService {
  final Map<String, _CachedProgram> _cache = <String, _CachedProgram>{};

  Future<CurrentEpgProgram?> currentProgram({
    required String? playlistUrl,
    required Channel channel,
  }) async {
    if (playlistUrl == null || !channel.id.startsWith('xtream_live_')) {
      return null;
    }
    final cached = _cache[channel.id];
    if (cached != null && cached.validUntil.isAfter(DateTime.now())) {
      return cached.program;
    }
    final streamId = channel.id.substring('xtream_live_'.length);
    final connection = _XtreamEpgConnection.tryParse(playlistUrl);
    if (connection == null || streamId.isEmpty) return null;
    try {
      final response = await http.get(
        connection.shortEpgUri(streamId),
        headers: const {
          'User-Agent': 'IPTVSmartersPlayer',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (payload is! Map || payload['epg_listings'] is! List) return null;
      final now = DateTime.now();
      CurrentEpgProgram? nearest;
      for (final raw in (payload['epg_listings'] as List).whereType<Map>()) {
        final start = _parseTime(raw['start_timestamp'] ?? raw['start']);
        final end = _parseTime(
          raw['stop_timestamp'] ?? raw['end_timestamp'] ?? raw['end'],
        );
        final title = _decodeProviderText(raw['title']);
        if (title.isEmpty) continue;
        final candidate = CurrentEpgProgram(title: title, endsAt: end);
        if (start != null &&
            end != null &&
            !now.isBefore(start) &&
            now.isBefore(end)) {
          nearest = candidate;
          break;
        }
        if (start == null || end == null) nearest ??= candidate;
      }
      if (nearest != null) {
        final expiry = nearest.endsAt != null && nearest.endsAt!.isAfter(now)
            ? nearest.endsAt!
            : now.add(const Duration(minutes: 3));
        _cache[channel.id] = _CachedProgram(nearest, expiry);
      }
      return nearest;
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseTime(dynamic raw) {
    if (raw == null) return null;
    final numeric = int.tryParse(raw.toString());
    if (numeric != null) {
      final milliseconds = numeric > 100000000000 ? numeric : numeric * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  String _decodeProviderText(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return '';
    try {
      final normalized = base64.normalize(value);
      final decoded =
          utf8.decode(base64.decode(normalized), allowMalformed: true);
      if (decoded.trim().isNotEmpty && !decoded.contains('\uFFFD')) {
        return decoded.trim();
      }
    } catch (_) {}
    return value;
  }
}

class _CachedProgram {
  const _CachedProgram(this.program, this.validUntil);
  final CurrentEpgProgram program;
  final DateTime validUntil;
}

class _XtreamEpgConnection {
  const _XtreamEpgConnection(this.source, this.username, this.password);
  final Uri source;
  final String username;
  final String password;

  static _XtreamEpgConnection? tryParse(String playlistUrl) {
    final uri = Uri.tryParse(playlistUrl.trim());
    if (uri == null || !uri.hasAuthority) return null;
    var username = uri.queryParameters['username']?.trim() ?? '';
    var password = uri.queryParameters['password']?.trim() ?? '';
    final segments = uri.pathSegments;
    final playlistIndex = segments.indexOf('playlist');
    if ((username.isEmpty || password.isEmpty) &&
        playlistIndex >= 0 &&
        segments.length > playlistIndex + 2) {
      username = segments[playlistIndex + 1];
      password = segments[playlistIndex + 2];
    }
    if (username.isEmpty || password.isEmpty) return null;
    return _XtreamEpgConnection(uri, username, password);
  }

  Uri shortEpgUri(String streamId) => source.replace(
        path: '/player_api.php',
        queryParameters: {
          'username': username,
          'password': password,
          'action': 'get_short_epg',
          'stream_id': streamId,
          'limit': '4',
        },
        fragment: '',
      );
}
