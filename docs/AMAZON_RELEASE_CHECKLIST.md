# TIVUQIPTV Amazon Release Kontrol Listesi

## Geri getirilemez anahtarlar

Aşağıdaki dosyalar kaynak kontrolüne alınmaz ve iki ayrı şifreli harici konuma
yedeklenmelidir:

- `android/tivuq-release.jks`
- `android/key.properties`
- `server/secrets/license-private.pem`
- `server/secrets/license-public.der`
- Her ticari derlemenin `build/protected-symbols/` klasörü

Android keystore kaybolursa aynı Amazon uygulamasına geliştirici imzalı güncelleme
hazırlanamaz. Sunucu özel anahtarı kaybolursa mevcut uygulamaların kabul edeceği
yeni lisans belgeleri üretilemez. Özel anahtarlar e-posta, Git veya herkese açık
bulut klasöründe tutulmamalıdır.

## Amazon'a ilk yükleme

1. Paket kimliğinin `com.tivuq.iptv` olduğunu doğrula.
2. APK/AAB dosyasını Amazon Developer Console'a yükle.
3. Amazon'un gösterdiği Appstore certificate SHA-256 değerini kaydet.
4. Appstore SDK kullanılmayan pakette `Apply Amazon DRM?` seçeneğini `Yes` yap.
5. Tek seferlik lisansı Amazon IAP içinde `entitlement` ürünü olarak oluştur;
   Appstore SDK satın alma akışını ve sunucu tarafı makbuz doğrulamasını tamamla.
6. Amazon paketinde QR, harici ödeme bağlantısı veya web sitesinden lisans satın
   alma çağrısı bulunmadığını doğrula.
7. Gerçek HTTPS alan adı, aktivasyon adresi, lisans sunucusu açık anahtarı ve
   Amazon SHA-256 değeriyle korumalı paketi yeniden üret.
8. Amazon App Tester ile başarılı, iptal edilmiş, bekleyen ve iade edilmiş satın
   alma cevaplarını doğrula.
9. Amazon test ortamından edinilen paketle Fire TV'de soğuk açılış, 30 günlük
   deneme, lisans, canlı TV, film ve dizi regresyonunu tamamla.

## Korumalı paket komutu

`scripts/build_protected_release.sh` şu değerler olmadan çalışmaz:

- `LICENSE_API_BASE_URL`
- `ACTIVATION_URL`
- `LICENSE_SERVER_PUBLIC_KEY`
- `OFFICIAL_SIGNING_CERT_SHA256`

Komut HTTPS dışındaki servisleri, eksik kalıcı keystore'u ve eksik Amazon
sertifikasını reddeder.
