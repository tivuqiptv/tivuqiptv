# Project Map (Playback System)

## Player UI & Components
- `lib/widgets/app_video_widget.dart`: Delegates rendering to active `PlayerAdapter.buildPlayerView()`.
- `lib/widgets/diagnostics_overlay_widget.dart`: Renders real-time metrics, video/audio codecs, HW/SW/UNKNOWN decoder badges, and async queueing status.

## Player Engine & Adapters
- `lib/services/player_engine.dart`: `AppPlayerEngine` wrapper orchestrating engine selection and adapter instantiation.
- `lib/player/player_adapter.dart`: Abstract interface contract for all player backends.
- `lib/player/firetv_media3_player_adapter.dart`: Native Media3 (ExoPlayer) adapter communicating over unified MethodChannel `com.tivuq.iptv/media3`.
- `lib/player/legacy_player_adapter.dart`: ExoPlayer (video_player) and media_kit fallback adapter.
- `lib/player/playback_diagnostics.dart`: Data model capturing real-time player telemetry.

## Android Native Media3 Core
- `android/app/src/main/kotlin/com/example/iptv_app/MainActivity.kt`: Registers `Media3PlayerPlugin` and `Media3Factory`.
- `android/app/src/main/kotlin/com/example/iptv_app/Media3PlayerPlugin.kt`: Static unified MethodChannel and EventChannel bridge handling player instantiation fallback and event listeners.
- `android/app/src/main/kotlin/com/example/iptv_app/Media3Factory.kt`: PlatformView factory instantiating native `Media3PlayerView`.
- `android/app/src/main/kotlin/com/example/iptv_app/Media3PlayerView.kt`: AndroidX Media3 ExoPlayer instance with `AnalyticsListener` metrics, async MediaCodec queueing (API 23+), track parsing, and hardware/software decoder classification.
