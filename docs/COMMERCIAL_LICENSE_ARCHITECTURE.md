# TIVUQIPTV Ticari Lisans Mimarisi

## Sabitlenen ilk kurallar

- Ürün: tek ödeme ile ömür boyu kullanım.
- Kapsam: bir lisans bir cihaz anahtarına bağlıdır.
- Cihaz kodu MAC adresi değildir; Android Keystore açık anahtarının kısa özetidir.
- Ham Android kimliği sunucuya gönderilmez. Cihaz ve resmi uygulama imzasından
  üretilen tek yönlü bağ, yeniden kurarak deneme süresini sıfırlamayı engeller.
- Yeniden kurulumda Keystore anahtarı değişirse aynı cihaz satırı yeni anahtara
  taşınır; kalan deneme veya satın alınmış lisans korunur.
- Özel cihaz anahtarı sunucuya veya APK'ya hiçbir zaman konmaz.
- Lisans hakkı veritabanında süresizdir.
- Uygulamaya verilen imzalı çevrimdışı belge yedi gün geçerlidir. Uygulama en az
  yedi günde bir sunucuya ulaşmalıdır. Bu pencere iade, chargeback ve kötüye
  kullanım iptallerinin uygulanabilmesi için gereklidir.
- Sunucu doğrulanamazsa yeni aktivasyon fail-closed çalışır; geçerli imzalı belge
  süresi dolana kadar mevcut lisans çevrimdışı kullanılabilir.

## Aktivasyon akışı

1. TIVUQIPTV Android Keystore içinde RSA cihaz anahtarı üretir.
2. Açık anahtarın SHA-256 özetinden okunabilir cihaz kodu türetilir.
3. Uygulama açık anahtarı ve cihaz kodunu sunucuya gönderir.
4. Sunucu iki dakika geçerli tek kullanımlık challenge üretir.
5. Fire TV challenge'ı Keystore özel anahtarıyla imzalar.
6. Sunucu imzayı açık anahtarla doğrular.
7. Aktif lisans varsa sunucu yedi günlük RS256 lisans belgesi üretir.
8. TIVUQIPTV gömülü sunucu açık anahtarıyla belgeyi ve cihaz kodunu doğrular.

## Kopyalamaya karşı sınır

Uygulama dosyası, SharedPreferences veya güvenli depolama başka cihaza kopyalansa
bile Android Keystore özel anahtarı kopyalanamadığı için challenge imzalanamaz.
Root edilmiş veya değiştirilmiş bir APK'ya karşı yüzde yüz güvenlik mümkün
değildir. Üretim APK'sı kalıcı TIVUQIPTV sertifikasını kendi içinde doğrular;
yeniden imzalanmış paket ticari lisans alamaz. R8 kaynak küçültme, Dart
obfuscation, sunucu kontrolleri ve anomali takibi kalan tersine mühendislik
maliyetini yükseltir.

## Veritabanı

- `devices`: açık anahtar, cihaz kodu, model, sürüm ve son görülme zamanı
- `licenses`: ömür boyu hak, durum, kaynak, aktivasyon ve iptal
- `customers`: ödeme/admin panelindeki müşteri kaydı
- `payments`: ödeme webhook'ları için idempotent sağlayıcı olayları
- `license_challenges`: kısa ömürlü, tek kullanımlık doğrulama soruları
- `audit_events`: admin, cihaz, ödeme ve güvenlik işlem geçmişi

## Tamamlanan altyapı

- Keystore cihaz kimliği, challenge/imza doğrulaması ve çevrimdışı lisans belgesi
- `com.tivuq.iptv` kalıcı paket kimliği ve TIVUQIPTV release sertifikası
- Üretim sertifikası öz-denetimi, R8 küçültme ve korumalı obfuscation betiği
- Amazon yükleme sırasında geliştirici imzasını hesaba özel Amazon imzasıyla
  değiştirir. Son mağaza derlemesine Developer Console'daki Amazon SHA-256
  sertifikası `OFFICIAL_SIGNING_CERT_SHA256` olarak verilir.
- Appstore yüklemesinde otomatik Amazon DRM açık seçilir; bu katman sideload
  edilmiş kopyanın Amazon kullanıcı yetkisini doğrulayamadan çalışmasını engeller.
- Amazon sürümündeki tek seferlik lisans Amazon IAP `entitlement` ürünüdür.
  Harici web ödemesi, ödeme QR'ı ve başka ödeme yöntemine yönlendirme Amazon
  paketinde gösterilmez. Web ödeme akışı yalnız ayrı Amazon dışı dağıtım içindir.
- Güvenli admin oturumu, cihaz/lisans ekranı ve işlem geçmişi
- Sipariş/ödeme şeması ve sağlayıcıdan bağımsız imzalı olay sözleşmesi
- Docker, Caddy/HTTPS, sağlık kontrolü ve PostgreSQL yedekleme betiği

## Sonraki aşamalar

1. Sunucu hesabı ve alan adı seçilerek staging ortamının gerçekten yayınlanması
2. Benzersiz Android application ID ve güvenli release signing anahtarı
3. Satış ülkesi, para birimi ve ödeme sağlayıcısının seçilmesi
4. Sağlayıcının gerçek imzalı webhook'u, iade ve chargeback akışı
5. Alarm, dış yedek deposu, gizlilik metni ve satış şartları

## Henüz kararlaştırılmayan ticari kurallar

- Yeni Fire TV alındığında ücretsiz cihaz taşıma sayısı ve bekleme süresi
- Fabrika ayarı/uygulama silme sonrası kimlik kurtarma yöntemi
- İade süresi ve chargeback politikası
- Desteklenen ülke, para birimi, vergi/fatura sağlayıcısı
- Amazon Appstore IAP mı, web üzerinden bağımsız ödeme mi kullanılacağı
