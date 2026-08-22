# Gizlilik ve Veri Beyanı Envanteri

Bu belge mağaza formunu, yayınlanan `/privacy` sayfasını ve gerçek backend
davranışını aynı tutmak için teknik kaynaktır. Yeni bir veri alanı, SDK veya
hizmet sağlayıcı eklendiğinde üçü birlikte güncellenmelidir.

## Ürün sınırı

- Uygulama kullanıcı tarafından sağlanan oynatma listesini oynatır.
- Sunucu kanal, film, dizi veya yayın aboneliği sağlamaz.
- Profil, favoriler, ayarlar ve izleme geçmişi cihazda tutulur; lisans
  backend'ine aktarılmaz.
- Reklam kimliği, konum, rehber, mikrofon ve kamera verisi toplanmaz.
- Kişisel veri satılmaz ve davranışsal reklam yapılmaz.

## Backend veri envanteri

| Veri | Amaç | Saklama | Silme davranışı |
| --- | --- | --- | --- |
| Cihaz kodu ve açık anahtar | Cihaz sahipliğini doğrulama | Lisans/deneme kullanımı boyunca | Doğrulanmış talepte anonimleştirilir |
| Tek yönlü cihaz bağı | Deneme ve lisans suistimalini önleme | Aktif kayıtta; silmeden sonra varsayılan 365 gün özet | Geri döndürülemez tombstone olarak kalır, sonra silinir |
| Model, platform, uygulama sürümü | Uyumluluk ve destek | Cihaz kaydı boyunca | Doğrulanmış talepte silinir |
| Deneme ve lisans tarihleri/durumu | 30 günlük deneme ve satın alma hakkı | Lisans kullanımı ve hukuki uyuşmazlık ihtiyacı boyunca | Kimlikten ayrıştırılır; lisans erişimi kapanır |
| Profil adı ve liste URL'si | Kullanıcının istediği telefondan kurulum | URL en fazla 10 dakika şifreli; eşleştirme metadatası varsayılan 30 gün | TV alınca veya süre dolunca URL hemen temizlenir |
| IP ve güvenlik olayı | Güvenlik, sahtekârlık, hata inceleme | Varsayılan 180 gün | Otomatik silinir; doğrulanmış talepte ilişkili alanlar anonimleştirilir |
| Yönetici oturumu | Panel güvenliği | Oturum bitene kadar | Süresi bitince otomatik silinir |
| Amazon işlem ve makbuz durumu | Satın alma, iade, ters ibraz | Vergi/muhasebe/iade mevzuatı süresince | Kart verisi hiç alınmaz; cihaz bağlantısı silme talebinde ayrıştırılır |
| Ödeme sağlayıcısının ham olayı | Webhook kanıtı ve hata inceleme | Varsayılan 30 gün | İçerik otomatik `{}` ile temizlenir |
| Gizlilik talebi | Talebin yerine getirildiğini kanıtlama | Tamamlandıktan sonra varsayılan 365 gün | Sonra otomatik silinir |

## Amazon privacy label karşılığı

Canlı sürümde mağaza formu doldurulurken `GET /privacy/data-disclosure.json`
çıktısı temel alınır. En az aşağıdakiler beyan edilir:

- Device identifiers: toplanır; uygulama işlevi, güvenlik ve sahtekârlığı önleme.
- Purchase history: Amazon IAP açıldığında toplanır; lisans sağlama, iade ve
  sahtekârlığı önleme.
- User-provided content: telefondan kurulum kullanılırsa profil adı ve liste
  adresi geçici işlenir.
- Diagnostics/security: IP ve güvenlik işlemleri sınırlı süre tutulur.
- Watch history: backend tarafından toplanmaz, yalnız cihazda kalır.
- Precise location, contacts, advertising ID: toplanmaz.

## Silme süreci

1. Cihaz yeni bir lisans challenge'ı alır.
2. Silme talebini cihazın Android Keystore özel anahtarıyla imzalar.
3. Backend talebi `pending` olarak yönetim paneline ekler.
4. Yönetici, ödeme/iade ve hukuki saklama ihtiyacını kontrol eder.
5. Tamamlama; cihaz kimliğini, açık anahtarı, modeli ve sürümü anonimleştirir,
   bekleyen liste verilerini siler, audit IP'lerini temizler ve cihazı kapatır.
6. Lisans bu cihazda kullanılamaz. İşlem geri döndürülemez olduğundan panel
   açık bir son onay ister.

## Yayından önce doldurulacak gerçek bilgiler

Üretim kontrolü aşağıdakiler gerçek değer olmadan başarılı olmaz:

- `PRIVACY_CONTROLLER_NAME`: gerçek kişi veya tüzel kişi adı.
- `PRIVACY_CONTACT_EMAIL`: takip edilen gizlilik e-posta adresi.
- `PRIVACY_EFFECTIVE_DATE`: yayınlanacak politika tarihi.
- Kullanılacak hosting, veritabanı, destek ve e-posta sağlayıcıları.
- Sağlayıcıların veri bölgeleri ve gerekiyorsa GDPR aktarım güvenceleri.
- Faaliyet ülkesine göre mali kayıtların kesin yasal saklama süresi.

Bu belge teknik uygunluk çalışmasıdır; şirketin faaliyet ülkesi ve satış
ülkeleri kesinleştiğinde yerel hukukçu tarafından son metin kontrolü yapılmalıdır.
