# TIVUQIPTV

Flutter ile geliştirilen, Fire TV ve Android TV odaklı IPTV istemcisi.

## Özellikler

- M3U ve yaygın Xtream playlist biçimleri
- Canlı TV, film ve dizi ayrımı
- AndroidX Media3 tabanlı native Fire TV oynatıcı
- Media3 açılamadığında Legacy ExoPlayer fallback
- Büyük playlistler için isolate tabanlı ayrıştırma ve yerel cache
- Profil bazlı kalıcı favoriler ve izleme geçmişi
- TV kumandası, kanal numarası girişi ve oynatma teşhis ekranı

## Geliştirme

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## Lisans yapılandırması

Üretim derlemesinde lisans sunucusu, aktivasyon sayfası ve lisans imza açık
anahtarı `dart-define` ile verilmelidir:

```bash
flutter build apk --release \
  --dart-define=LICENSE_API_BASE_URL=https://api.example.com \
  --dart-define=ACTIVATION_URL=https://example.com/activate \
  --dart-define=LICENSE_SERVER_PUBLIC_KEY=BASE64URL_DER_PUBLIC_KEY
```

TIVUQIPTV cihaz anahtarını Android Keystore içinde üretir. Lisans sunucusu tek
kullanımlık challenge ile bu anahtarın cihazda bulunduğunu doğrular ve imzalı,
süreli bir çevrimdışı lisans belgesi verir. Sunucu uygulaması, PostgreSQL şeması
ve işletim adımları [server/README.md](server/README.md) altındadır.

Yapılandırma olmadan deneme süresi dolan cihaz fail-closed davranır; aktivasyon
ekranı uygulamayı doğrulamasız açmaz.

## HTTP IPTV sunucuları

Uygulama, kullanıcı tarafından açıkça girilen `http://` IPTV sunucularını Fire TV’de
destekler. Bir `https://` adresi hata verdiğinde güvenlik nedeniyle otomatik olarak
HTTP’ye düşürülmez.

## Release

Kalıcı Android kimliği `com.tivuq.iptv`, TIVUQIPTV release keystore'u,
R8/resource shrinking ve Dart obfuscation akışı hazırdır. Ticari paket yalnız
gerçek HTTPS lisans/aktivasyon adresleri ve Amazon Appstore sertifika SHA-256
değeri verilince `scripts/build_protected_release.sh` ile üretilir.

Amazon'a gönderim ve kritik anahtar yedekleri için
[Amazon release kontrol listesine](docs/AMAZON_RELEASE_CHECKLIST.md) bakın.
