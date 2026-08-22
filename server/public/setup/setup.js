const form = document.querySelector('#setup-form');
const message = document.querySelector('#message');
const button = form.querySelector('button');

const translations = {
  en: {
    pageTitle: 'TIVUQIPTV — Send Playlist to TV', remoteSetup: 'Remote Setup',
    eyebrow: 'NO REMOTE TYPING NEEDED', heading: 'Send your playlist to your TV',
    description: 'Scan the QR code on your TV. The device and temporary setup codes are filled in automatically.',
    deviceCode: 'Device code', pairingCode: 'Temporary setup code', profileName: 'Profile name',
    profilePlaceholder: 'Home', playlistUrl: 'Personal M3U / IPTV playlist address',
    privacy: 'Your address is encrypted during transfer and removed from the server after the TV receives it.',
    privacyLink: 'Privacy Policy',
    submit: 'Send to TV', success: 'The playlist was sent to your TV and will be added in a few seconds.',
    invalid: 'The device or setup code is incorrect or expired.', failed: 'Transfer failed.',
  },
  de: {
    pageTitle: 'TIVUQIPTV — Senderliste an TV senden', remoteSetup: 'Remote-Einrichtung',
    eyebrow: 'KEINE EINGABE MIT DER FERNBEDIENUNG', heading: 'Senderliste an den TV senden',
    description: 'Scannen Sie den QR-Code auf dem TV. Geräte- und Einrichtungscode werden automatisch ausgefüllt.',
    deviceCode: 'Gerätecode', pairingCode: 'Temporärer Einrichtungscode', profileName: 'Profilname',
    profilePlaceholder: 'Zuhause', playlistUrl: 'Persönliche M3U-/IPTV-Listenadresse',
    privacy: 'Ihre Adresse wird verschlüsselt übertragen und nach Empfang durch den TV vom Server entfernt.',
    privacyLink: 'Datenschutzerklärung',
    submit: 'An TV senden', success: 'Die Senderliste wurde gesendet und wird in wenigen Sekunden hinzugefügt.',
    invalid: 'Der Geräte- oder Einrichtungscode ist falsch oder abgelaufen.', failed: 'Übertragung fehlgeschlagen.',
  },
  tr: {
    pageTitle: 'TIVUQIPTV — TV’ye Liste Gönder', remoteSetup: 'Uzaktan Kurulum',
    eyebrow: 'KUMANDAYLA YAZMAYA GEREK YOK', heading: 'Listenizi TV’ye gönderin',
    description: 'TV’deki QR kodu okutun. Cihaz ve geçici kurulum kodları otomatik doldurulur.',
    deviceCode: 'Cihaz kodu', pairingCode: 'Geçici kurulum kodu', profileName: 'Profil adı',
    profilePlaceholder: 'Ev', playlistUrl: 'Kişisel M3U / IPTV liste adresi',
    privacy: 'Adresiniz şifreli aktarılır ve TV aldıktan sonra sunucudan silinir.',
    privacyLink: 'Gizlilik Politikası',
    submit: 'TV’ye Gönder', success: 'Liste TV’ye gönderildi ve birkaç saniye içinde eklenecek.',
    invalid: 'Cihaz veya kurulum kodu yanlış ya da süresi dolmuş.', failed: 'Gönderim başarısız.',
  },
};

const language = ['en', 'de', 'tr'].includes(navigator.language.slice(0, 2).toLowerCase())
  ? navigator.language.slice(0, 2).toLowerCase() : 'en';
const strings = translations[language];
document.documentElement.lang = language;
document.title = strings.pageTitle;
document.querySelectorAll('[data-i18n]').forEach((element) => {
  const value = strings[element.dataset.i18n];
  if (value) element.textContent = value;
});
document.querySelectorAll('[data-i18n-placeholder]').forEach((element) => {
  const value = strings[element.dataset.i18nPlaceholder];
  if (value) element.placeholder = value;
});

const query = new URLSearchParams(window.location.search);
document.querySelector('#device-code').value = query.get('deviceCode') ?? '';
document.querySelector('#pairing-code').value = query.get('pairingCode') ?? '';

document.querySelector('#device-code').addEventListener('input', (event) => {
  const raw = event.target.value.toUpperCase().replace(/[^0-9A-F]/g, '').slice(0, 12);
  event.target.value = raw.match(/.{1,4}/g)?.join('-') ?? raw;
});
document.querySelector('#pairing-code').addEventListener('input', (event) => {
  event.target.value = event.target.value.replace(/\D/g, '').slice(0, 8);
});

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  message.textContent = '';
  message.className = '';
  button.disabled = true;
  try {
    const response = await fetch('/v1/setup/profile', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        deviceCode: document.querySelector('#device-code').value,
        pairingCode: document.querySelector('#pairing-code').value,
        profileName: document.querySelector('#profile-name').value,
        playlistUrl: document.querySelector('#playlist-url').value,
      }),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(result.error || 'transfer_failed');
    message.className = 'success';
    message.textContent = strings.success;
    form.reset();
  } catch (error) {
    message.className = 'error';
    message.textContent = error.message === 'pairing_not_found_or_code_invalid'
      ? strings.invalid
      : strings.failed;
  } finally {
    button.disabled = false;
  }
});
