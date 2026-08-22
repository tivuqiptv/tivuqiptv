import 'package:flutter/widgets.dart';
import 'playback_diagnostics.dart';

class PlayerTrackOption {
  const PlayerTrackOption({
    required this.id,
    required this.label,
    this.language,
    this.isSelected = false,
    this.isOff = false,
  });

  final String id;
  final String label;
  final String? language;
  final bool isSelected;
  final bool isOff;
}

abstract class PlayerAdapter {
  Stream<bool> get isBufferingStream;
  Stream<bool> get isPlayingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<PlaybackDiagnostics> get diagnosticsStream;

  Widget buildPlayerView({BoxFit fit = BoxFit.contain});

  Future<void> openUrl(
    String url, {
    double volume = 72.0,
    bool enableTunneling = false,
    String quality = 'auto',
    Map<String, String> httpHeaders = const {},
  });
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setTunneling(bool enabled);
  Future<PlaybackDiagnostics> getDiagnostics();
  Future<List<PlayerTrackOption>> getAudioTracks() async => const [];
  Future<List<PlayerTrackOption>> getSubtitleTracks() async => const [];
  Future<void> selectAudioTrack(String id) async {}
  Future<void> selectSubtitleTrack(String id) async {}

  bool get isInitialized;
  bool get isPlaying;
  Duration get position;
  Duration get duration;

  Future<void> dispose();
}
