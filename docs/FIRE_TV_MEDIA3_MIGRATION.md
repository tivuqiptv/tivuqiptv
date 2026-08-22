# Fire TV Media3 Native Player Migration Plan

## 1. Selected Architecture
- **Platform Abstraction**: Clean `PlayerAdapter` contract (`lib/player/player_adapter.dart`).
- **Engines**:
  1. `LegacyPlayerAdapter` (Wraps existing `AppPlayerEngine` for 100% safe fallback).
  2. `FireTvMedia3PlayerAdapter` (Native AndroidX Media3 ExoPlayer plugin via PlatformView / SurfaceView with hardware acceleration, tunneled playback capability detection, async MediaCodec queueing, and AC3/E-AC3 audio decoders).
- **Diagnostics**: Real-time `PlaybackDiagnostics` overlay for FPS, dropped frames, decoder type, resolution, bitrate, buffer duration, audio codec, and hardware vs software status.
- **Feature Flag**: Runtime toggle between `Legacy` and `Native Media3`.

## 2. Target Files
- `lib/player/player_adapter.dart` [NEW]
- `lib/player/legacy_player_adapter.dart` [NEW]
- `lib/player/firetv_media3_player_adapter.dart` [NEW]
- `lib/player/playback_diagnostics.dart` [NEW]
- `lib/widgets/diagnostics_overlay_widget.dart` [NEW]
- `android/app/src/main/kotlin/com/example/iptv_app/Media3PlayerView.kt` [NEW]
- `android/app/src/main/kotlin/com/example/iptv_app/Media3PlayerPlugin.kt` [NEW]
- `android/app/src/main/kotlin/com/example/iptv_app/MainActivity.kt` [MODIFY]
- `android/app/build.gradle.kts` [MODIFY]

## 3. Risk Mitigation & Rollback
- Default fallback remains `LegacyPlayerAdapter` if native Media3 plugin initialization fails or is disabled.
- Zero UI redesign; existing FocusNodes, remote listeners, overlay bars, and Xtream/M3U parsers remain completely untouched.
