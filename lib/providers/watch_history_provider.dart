import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchHistory {
  final int position;
  final int duration;
  final DateTime? lastWatchedAt;

  const WatchHistory({
    required this.position,
    required this.duration,
    this.lastWatchedAt,
  });

  double get percent =>
      duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;
  int get remainingMinutes =>
      duration > 0 ? ((duration - position) / 60).floor() : 0;
  bool get isCompleted => percent > 0.95;

  Map<String, dynamic> toMap() => {
        'position': position,
        'duration': duration,
        'lastWatchedAt': lastWatchedAt?.toUtc().toIso8601String(),
      };

  factory WatchHistory.fromMap(Map<String, dynamic> map) {
    return WatchHistory(
      position: (map['position'] as num?)?.toInt() ?? 0,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      lastWatchedAt: map['lastWatchedAt'] == null
          ? null
          : DateTime.tryParse(map['lastWatchedAt'].toString())?.toUtc(),
    );
  }
}

class WatchHistoryProvider extends ChangeNotifier {
  static const _storageKey = 'watch_history_v2';
  static const _separator = '\u001f';

  SharedPreferences? _prefs;
  bool _isInitialized = false;
  int _recentRevision = 0;
  final Map<String, WatchHistory> _historyMap = {};
  final Map<String, WatchHistory> _legacyHistoryMap = {};

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      final encoded = _prefs!.getString(_storageKey);
      if (encoded != null) {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is Map) {
              _historyMap[entry.key.toString()] = WatchHistory.fromMap(
                Map<String, dynamic>.from(entry.value as Map),
              );
            }
          }
        }
      }

      // Keep old progress bars/resume positions working. Legacy records have
      // no reliable profile or timestamp, so they are intentionally not used
      // in the new profile-specific "recently watched" category.
      final keys = _prefs!.getKeys().where(
            (key) => key.startsWith('hist_pos_'),
          );
      for (final key in keys) {
        final videoId = key.replaceFirst('hist_pos_', '');
        final position = _prefs!.getInt('hist_pos_$videoId') ?? 0;
        final duration = _prefs!.getInt('hist_dur_$videoId') ?? 0;
        if (position > 0 && duration > 0) {
          _legacyHistoryMap[videoId] = WatchHistory(
            position: position,
            duration: duration,
          );
        }
      }
    } catch (error) {
      debugPrint('İzleme geçmişi yüklenemedi: ${error.runtimeType}');
    }

    _isInitialized = true;
    _recentRevision++;
    notifyListeners();
  }

  bool get isInitialized => _isInitialized;
  int get recentRevision => _recentRevision;

  Future<void> markWatched(
    String videoId, {
    String? profileId,
    DateTime? watchedAt,
  }) async {
    if (videoId.isEmpty) return;
    final key = _scopedKey(profileId, videoId);
    final existing = _historyMap[key];
    _historyMap[key] = WatchHistory(
      position: existing?.position ?? 0,
      duration: existing?.duration ?? 1,
      lastWatchedAt: (watchedAt ?? DateTime.now()).toUtc(),
    );
    _pruneProfile(profileId);
    _recentRevision++;
    await _persist();
    notifyListeners();
  }

  WatchHistory? getProgress(String videoId, {String? profileId}) {
    final scoped = _historyMap[_scopedKey(profileId, videoId)];
    return scoped ?? _legacyHistoryMap[videoId];
  }

  DateTime? getLastWatchedAt(String videoId, {required String profileId}) {
    return _historyMap[_scopedKey(profileId, videoId)]?.lastWatchedAt;
  }

  List<String> recentlyWatchedIds(String profileId, {int limit = 50}) {
    final prefix = '$profileId$_separator';
    final entries = _historyMap.entries
        .where(
          (entry) =>
              entry.key.startsWith(prefix) && entry.value.lastWatchedAt != null,
        )
        .toList()
      ..sort(
        (a, b) => b.value.lastWatchedAt!.compareTo(a.value.lastWatchedAt!),
      );
    return entries
        .take(limit)
        .map((entry) => entry.key.substring(prefix.length))
        .toList(growable: false);
  }

  Future<void> saveProgress(
    String videoId,
    int positionInSeconds,
    int durationInSeconds, {
    String? profileId,
    DateTime? watchedAt,
  }) async {
    if (durationInSeconds <= 0 || videoId.isEmpty) return;

    final key = _scopedKey(profileId, videoId);
    final wasNotRecentlyWatched = _historyMap[key]?.lastWatchedAt == null;
    final history = WatchHistory(
      position: positionInSeconds,
      duration: durationInSeconds,
      lastWatchedAt: (watchedAt ?? DateTime.now()).toUtc(),
    );
    _historyMap[key] = history;
    if (wasNotRecentlyWatched) _recentRevision++;
    _pruneProfile(profileId);
    await _persist();
    notifyListeners();
  }

  String _scopedKey(String? profileId, String videoId) {
    final owner =
        profileId?.trim().isNotEmpty == true ? profileId!.trim() : 'global';
    return '$owner$_separator$videoId';
  }

  void _pruneProfile(String? profileId) {
    final owner =
        profileId?.trim().isNotEmpty == true ? profileId!.trim() : 'global';
    final prefix = '$owner$_separator';
    final entries = _historyMap.entries
        .where((entry) => entry.key.startsWith(prefix))
        .toList()
      ..sort((a, b) {
        final aDate =
            a.value.lastWatchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.value.lastWatchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    for (final entry in entries.skip(600)) {
      _historyMap.remove(entry.key);
    }
  }

  Future<void> _persist() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      for (final entry in _historyMap.entries) entry.key: entry.value.toMap(),
    });
    await prefs.setString(_storageKey, encoded);
  }
}
