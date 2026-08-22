# Supabase + Vercel kurulumu

Bu kurulumda Flutter/Fire TV uygulaması Supabase'e doğrudan bağlanmaz. Uygulama
yalnız HTTPS üzerinden Vercel API adresini kullanır. Veritabanı parolası, lisans
özel anahtarı ve admin sırları yalnız Vercel ortam değişkenlerinde kalır.

## 1. Supabase

1. Supabase'te bir proje oluşturun ve mümkünse müşterilerinize yakın bir Avrupa
   bölgesi seçin.
2. **Connect** ekranından iki bağlantıyı alın:
   - `MIGRATION_DATABASE_URL`: Direct bağlantı veya IPv4 gerekiyorsa Session
     pooler, port `5432`.
   - `DATABASE_URL`: Vercel çalışma zamanı için Transaction pooler, port `6543`.
3. Yerel terminalde `server/` klasöründe migration'ları çalıştırın:

   ```bash
   MIGRATION_DATABASE_URL='postgresql://...' npm run db:migrate
   ```

4. Supabase **SQL Editor** içinde sırasıyla `supabase/hardening.sql` ve
   `supabase/cron.sql` dosyalarını çalıştırın.
5. Cron ekranında `tivuq-hourly-maintenance` işinin oluştuğunu doğrulayın.

`hardening.sql`, Supabase'in `anon` ve `authenticated` rollerinin lisans
tablolarını Data API üzerinden görmesini engeller. Vercel, sunucu tarafındaki
Postgres rolüyle çalışmaya devam eder.

## 2. Vercel

1. Yeni Vercel projesinde kök dizin olarak `server` klasörünü seçin.
2. Framework Preset değerini **Other** bırakın.
3. Aşağıdaki ortam değişkenlerini Production, Preview ve Development için
   tanımlayın:

   ```dotenv
   DATABASE_URL=postgresql://...pooler.supabase.com:6543/postgres
   DATABASE_POOL_MAX=1
   ADMIN_API_TOKEN=...
   ADMIN_EMAIL=...
   ADMIN_PASSWORD=...
   LICENSE_SIGNING_PRIVATE_KEY_BASE64=...
   LICENSE_TOKEN_TTL_SECONDS=604800
   ADMIN_SESSION_TTL_SECONDS=43200
   PUBLIC_BASE_URL=https://proje-adiniz.vercel.app
   TRUST_PROXY=true
   REMOTE_PROFILE_ENCRYPTION_SECRET=...
   PRIVACY_CONTROLLER_NAME=...
   PRIVACY_CONTACT_EMAIL=...
   PRIVACY_EFFECTIVE_DATE=YYYY-MM-DD
   AUDIT_RETENTION_DAYS=180
   PAIRING_METADATA_RETENTION_DAYS=30
   PAYMENT_RAW_EVENT_RETENTION_DAYS=30
   PRIVACY_REQUEST_RETENTION_DAYS=365
   DEVICE_TOMBSTONE_RETENTION_DAYS=365
   ```

4. Özel anahtarı tek satırlık base64 değere dönüştürün; anahtar dosyasını
   Vercel'e veya Git'e yüklemeyin:

   ```bash
   base64 < secrets/license-private.pem | tr -d '\n'
   ```

5. Vercel Function bölgesini Supabase projesinin bölgesine en yakın bölgeye
   ayarlayın ve deploy edin.
6. Deploy sonrası şunları kontrol edin:

   ```text
   https://proje-adiniz.vercel.app/health
   https://proje-adiniz.vercel.app/admin
   https://proje-adiniz.vercel.app/setup
   https://proje-adiniz.vercel.app/privacy
   ```

## 3. Uygulama bağlantısı

Vercel adresi kesinleşince Flutter derlemesindeki lisans API taban adresi yalnız
bir kez bu HTTPS adresine çevrilir. Bu son adıma kadar mevcut çalışan Fire TV
derlemesine dokunulmaz.

## Operasyon notları

- Vercel Function sürekli açık bir sunucu süreci değildir; her istek bağımsız
  işlenir. Lisans ve oturum durumu Supabase'te tutulduğu için süreç kapanması
  veri veya oturum kaybettirmez.
- Supabase Free proje düşük etkinlikte otomatik duraklatılabilir; kesintisiz
  ticari üretimde otomatik duraklatması olmayan ücretli plan kullanılmalıdır.
- Vercel Hobby yalnız kişisel ve ticari olmayan kullanım içindir. Ücretli
  TIVUQIPTV yayını Vercel Pro veya uygun bir ticari plan üzerinde olmalıdır.
- Plan fiyatları ve limitleri değişebildiği için satın alma günü iki sağlayıcının
  güncel fiyat/limit sayfası yeniden kontrol edilmelidir.
- Runtime bağlantısı `6543` Transaction pooler üzerinden, migration bağlantısı
  `5432` Direct/Session üzerinden yapılır.
