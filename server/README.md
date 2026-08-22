# TIVUQIPTV License Server

TIVUQIPTV'nin cihaz anahtarıyla bağlı, tek ödemelik ömür boyu lisans çekirdeği ve
görsel yönetim panelidir. Ödeme sağlayıcısı sonraki katmandır ve aynı lisans
altyapısını kullanacaktır.

## Güvenlik modeli

- Cihaz RSA özel anahtarını Android Keystore içinde üretir; sunucuya yalnızca açık
  anahtar gönderilir.
- Cihaz kodu açık anahtarın SHA-256 özetinden türetilir.
- Her kontrol için iki dakika geçerli, tek kullanımlık challenge üretilir.
- Lisans yalnızca challenge'ı cihaz anahtarıyla imzalayan cihaza verilir.
- Çevrimdışı lisans belgesi sunucunun RSA anahtarıyla imzalanır ve yedi gün
  geçerlidir. Süresiz satın alma hakkı veritabanında süresizdir; yedi gün yalnızca
  iptal/iade bilgisinin cihaza ulaşabileceği çevrimdışı penceredir.

## Yerel kurulum

1. `npm install`
2. `npm run keys:generate`
3. `docker compose up -d postgres`
4. `.env.example` dosyasını `.env` olarak kopyalayıp güçlü değerler girin.
5. Ortam değişkenlerini yükleyip `npm run db:migrate` çalıştırın.
6. `npm start`

## Yönetim paneli

Sunucu çalışırken paneli tarayıcıdan açın:

```text
http://127.0.0.1:8080/admin
```

Giriş hesabı ilk çalıştırmada aşağıdaki ortam değişkenlerinden oluşturulur:

```dotenv
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=replace-with-at-least-12-characters
```

Panelden kayıtlı cihazları görebilir, cihaz veya müşteri arayabilir, ömür boyu
lisans açabilir, lisansı iptal edebilir, ödeme kayıtlarını ve son 250 güvenlik
işlemini inceleyebilirsiniz. Oturum anahtarı veritabanında
yalnızca SHA-256 özetiyle tutulur; tarayıcıya `HttpOnly`, `SameSite=Strict`
çerez olarak verilir. Üretimde paneli mutlaka HTTPS üzerinden yayınlayın.

Üretimde özel anahtarı Git'e, APK'ya veya admin paneline koymayın. HTTPS ters
proxy, yönetilen PostgreSQL, günlük yedekleme ve secret manager kullanın.

## İlk manuel aktivasyon

Uygulama aktivasyon ekranını bir kez yenileyince cihaz sunucuda görünür:

```bash
curl -H "Authorization: Bearer $ADMIN_API_TOKEN" \
  https://api.example.com/v1/admin/devices
```

Lisans açma:

```bash
curl -X POST \
  -H "Authorization: Bearer $ADMIN_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"deviceCode":"ABCD-1234-EF56","customerEmail":"user@example.com"}' \
  https://api.example.com/v1/admin/licenses/activate
```

Bu uç nokta ileride ödeme webhook'u tarafından çağrılmayacak; ödeme sağlayıcısı
için ayrı, imzası doğrulanan ve idempotent bir webhook oluşturulacaktır.

## Ödeme entegrasyonu durumu

Sipariş ve ödeme tabloları, sağlayıcı olay kimliğine göre idempotent kayıt yapısı
ve imzalı webhook sözleşmesi hazırdır. Gerçek webhook uç noktası bilinçli olarak
kapalıdır: ödeme sağlayıcısı ve satış ülkesi seçildikten sonra sağlayıcının kendi
imza biçimi doğrulanarak açılacaktır. İmzası doğrulanmayan istemci verisiyle
lisans açılamaz.

## Gizlilik ve veri yaşam döngüsü

- Her dilde yayınlanan politika: `GET /privacy` (`?lang=en`, `de`, `tr`)
- Amazon veri beyanı için makinece okunabilir envanter:
  `GET /privacy/data-disclosure.json`
- Cihaz anahtarıyla doğrulanan silme talebi:
  `POST /v1/privacy/deletion-requests`
- Bekleyen talepler yönetim panelindeki **Veri Silme Talepleri** bölümünde
  incelenir ve son onayla anonimleştirilir.
- Liste URL'si TV tarafından alındığında veya 10 dakika dolduğunda temizlenir.
  Audit, eşleştirme metadatası, ham ödeme olayı ve tamamlanmış gizlilik talepleri
  yapılandırılan sürelerde otomatik temizlenir.

Mağaza formunu doldurmadan önce
[`docs/PRIVACY_DATA_INVENTORY.md`](../docs/PRIVACY_DATA_INVENTORY.md) ile canlı
sağlayıcı ve politika bilgilerinin tamamlandığını doğrulayın.

## Üretim

Docker/Caddy yapılandırması için [deploy/README.md](deploy/README.md) dosyasına
bakın. Canlıya almadan önce `.env` yüklenmiş halde `npm run production:check`
çalıştırın.

Supabase PostgreSQL + Vercel Functions kurulumu için
[supabase/README.md](supabase/README.md) dosyasındaki sırayı kullanın. Bu mimari
kalıcı süreç veya uygulama belleğine güvenmez; hız sınırları dahil çalışma durumu
PostgreSQL'de, periyodik temizlik Supabase Cron'da tutulur.
