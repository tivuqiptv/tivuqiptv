# TIVUQIPTV üretim kurulumu

## Sunucu gereksinimi

- Ubuntu 24.04 veya güncel bir Linux sunucu
- En az 2 GB RAM, 1 paylaşımlı CPU ve 20 GB SSD
- Sunucu IP adresine yönlendirilmiş bir alan adı
- Docker Engine ve Docker Compose

## İlk kurulum

1. `server` klasörünü sunucuya aktarın.
2. `.env.production.example` dosyasını `.env` olarak kopyalayıp tüm değerleri
   uzun ve rastgele değerlerle değiştirin.
3. `npm run keys:generate` ile lisans anahtarlarını `secrets` klasöründe üretin.
4. `docker compose --env-file .env -f compose.production.yaml up -d --build`
   komutunu çalıştırın.
5. `https://alan-adiniz/admin` ve `https://alan-adiniz/health` adreslerini
   kontrol edin.

Müşterinin telefondan kişisel liste adresini TV'ye göndereceği sayfa
`https://alan-adiniz/setup` adresindedir. `REMOTE_PROFILE_ENCRYPTION_SECRET`
değeri en az 32 rastgele karakter olmalı ve kurulumdan sonra değiştirilmemelidir;
değiştirilirse henüz TV tarafından alınmamış bekleyen profiller çözülemez.

Caddy geçerli DNS kaydı bulunduğunda TLS sertifikasını otomatik alır ve yeniler.
PostgreSQL internete port açmaz; yalnızca uygulamanın özel Docker ağına bağlıdır.

## Yedekleme

`scripts/backup.sh` günlük zamanlayıcıya eklenmelidir. Yedek dosyasının ayrıca
başka bir sunucuya veya şifreli nesne deposuna kopyalanması gerekir. Ayda en az
bir kez boş bir veritabanına geri yükleme testi yapılmalıdır.
