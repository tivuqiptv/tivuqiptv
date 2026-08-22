# Playback Baseline Document

## Verified Current Player Architecture
- **Flutter Packages**: `video_player` (2.13.0 / `video_player_android` 2.12.0) and `media_kit` (1.1.10) fallback.
- **Actual Android Playback Engine**: Native player dependencies are consistently pinned to AndroidX Media3 `1.11.0`; the Legacy path uses the version resolved by `video_player_android`.
- **Media3 Version Decision**: Keep every explicitly referenced Media3 module on the same `1.11.0` version. Validate upgrades on the physical Fire TV matrix before changing this pin.
- **Asynchronous MediaCodec Queueing**:
  - Implemented via `DefaultRenderersFactory.forceEnableMediaCodecAsynchronousQueueing()`.
  - Condition: Enforced on Android 6.0+ (`Build.VERSION.SDK_INT >= Build.VERSION_CODES.M` / API 23+).
  - Decoder Fallback: Separately enabled via `setEnableDecoderFallback(true)`.
  - Diagnostic Tracking: `asyncCodecQueueing` flag exposed in real-time metrics map.
- **Rendering Mechanism**: `PlatformView` / `PlayerView` (Native Media3) and `TextureView` (Legacy).
- **Video Decoder Path**: Android `MediaCodec` hardware decoders via ExoPlayer pipeline with async queueing.
- **Audio Decoder Path**: Android `MediaCodecAudioRenderer` / `AudioTrack` with capability-based track selection.
- **Existing Buffering Settings**: `DefaultLoadControl` (minBuffer=15s, maxBuffer=50s, bufferForPlayback=1.5s).
- **Stream Handling**: HLS (`.m3u8` via `HlsMediaSource`), MPEG-TS (`.ts` via `ProgressiveMediaSource`), HTTP headers (`User-Agent: IPTVSmartersPlayer`).

## TV Input & Remote Control Baseline
- **UP / DOWN**: Relative channel navigation (+1 / -1) when watching; menu navigation when sidebar open.
- **LEFT / RIGHT**: Seek (-10s / +10s) in VOD player; category navigation in Live TV.
- **OK / ENTER**: Toggle controls / select focused channel.
- **BACK**: Close overlay / return to navigation / exit app.
- **NUMERIC DIGITS (0-9)**: Direct channel number entry with 1.8-second auto-submit timer.
