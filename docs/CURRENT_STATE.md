# Current State (Rollback Complete — Stable Media3 Baseline)

## Canlı TV Ekran Kipi
- **Canlı TV**: Ayarlarda 50 Hz seçiliyse ekran canlı TV'ye girerken bir kez 50p'ye; 60 Hz seçiliyse 60p ailesine alınır. Kanal değişimlerinde ikinci bir HDMI/el sıkışma isteği gönderilmez.
- **Film ve Dizi**: Canlı TV'nin sabit ekran kipi kullanılmaz; uygulama açılışında kayıtlı canlı TV kipi uygulanmaz ve VOD'a geçerken normal 60p ekran kipine dönülür.
- **Motor Sırası**: Ayarlarda seçilen motor her yayında ilk denenir. Varsayılan ExoPlayer2 başarısız olursa Media3 denenir; ikinci motor da başarısız olursa yayın hatası gösterilir.
- **Yanlış Fallback Koruması**: ExoPlayer2 `READY` olduktan sonra ses tablosu geciken veya sessiz olan yayınlar geçerli kabul edilir. Media3'e yalnızca ses izi mevcut ve codec açıkça desteklenmiyorsa geçilir.
- **Normal Kullanım Yükü**: Kare-zamanlama örnekleme, sıralama, loglama ve periyodik native tanılama sorguları yalnızca tanılama ekranı açıkken çalışır.
- **Kanal Geçiş & Render Stabilitesi**:
  - `Media3PlayerView` ve `SurfaceView` render yolu eski kararlı yapısına döndürülmüştür. Kanal geçişlerinde eski kare kalması sorunu tamamen çözülmüş, ses/video senkronizasyonu ve hızlı kanal değişimi yeniden tam stabil hale getirilmiştir.

## Build Verification Results
- Verification results must be refreshed after every playback change; see the latest implementation report rather than treating this file as a permanent test result.
- Native Media3 errors are propagated to Flutter and trigger a Legacy ExoPlayer fallback.
- Playback quality is forwarded to the native track selector; tunneling remains opt-in.
