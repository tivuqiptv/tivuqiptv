# TIVUQIPTV Telefon Uygulaması Yol Haritası

TV uygulamasına bağlı, Android ve iOS için ortak Flutter telefon uygulaması
geliştirilecektir.

## Planlanan temel özellikler

- TV ekranındaki kısa ömürlü QR ile güvenli cihaz eşleştirme
- M3U/IPTV liste adresini ve profil bilgisini TV'ye gönderme
- Profil, favori ve izleme geçmişi yönetimi
- Kanal arama ve kanal değiştirme
- Oynat/duraklat, ileri/geri sarma ve yön tuşlu kumanda
- Aynı hesaptaki birden fazla TV'yi yönetme
- Uygulama yüklüyse deep link ile açılan, değilse resmi mobil mağazaya yönelen QR

## Güvenlik kuralları

- Liste adresi QR içine veya kalıcı loglara yazılmaz.
- Eşleştirme kodu 10 dakika geçerli, tek kullanımlık ve deneme sınırına tabidir.
- TV komutları cihaz başına iptal edilebilir yetki anahtarıyla imzalanır.
- Yerel ağ kontrolü kimlik doğrulamasız port açmaz.
- Mobil uygulama hazır olmadan TV içinde indirme bağlantısı gösterilmez.
