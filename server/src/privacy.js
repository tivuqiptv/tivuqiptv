const policies = {
  en: {
    title: 'Privacy Policy', languageName: 'English', updated: 'Effective date',
    intro: (name) => `${name} provides a media-player application. We do not provide channels, films, series, or subscriptions to third-party media services. Users add their own playlist address and are responsible for having the rights required to access that content.`,
    controller: 'Data controller', contact: 'Privacy contact',
    collectedTitle: 'Data we process',
    collected: [
      ['Device and licensing data', 'Device code, public device key, one-way device binding, device model, platform, app version, trial dates, license status, and last verification time.'],
      ['Remote playlist setup', 'Profile name and playlist address entered by the user. The payload is encrypted while briefly waiting for the TV and the playlist address is erased from the server immediately after retrieval or expiry.'],
      ['Security and operations', 'IP address, request time, security event, limited user-agent information for administrators, and authentication/session records.'],
      ['Purchases', 'When purchases are enabled: Amazon transaction identifiers, product, price, currency, purchase status, and refund or chargeback status. Payment-card details are handled by Amazon and are not received by us.'],
      ['On-device data', 'Profiles, favorites, settings, and watch history are stored on the device. They are not uploaded to the licensing service unless a feature explicitly says so.'],
    ],
    purposesTitle: 'Why we process data',
    purposes: 'We process data to start and enforce the 30-day trial, bind a license to the correct device, restore and verify purchases, provide user-requested remote setup, prevent fraud and trial abuse, secure the service, diagnose failures, meet legal obligations, and answer privacy requests. We do not use the data for behavioral advertising and we do not sell personal data.',
    legalTitle: 'Legal bases',
    legal: 'Where the GDPR applies, processing is based on performance of the service contract, steps requested before entering a contract, our legitimate interests in service security and fraud prevention, compliance with legal obligations for financial records, and consent where the law specifically requires it.',
    retentionTitle: 'Retention',
    retention: (r) => [
      `Playlist payload: until the TV retrieves it, or at most 10 minutes. Pairing metadata: ${r.pairingMetadataDays} days.`,
      `License challenges: at most 24 hours. Security/audit events: ${r.auditDays} days. Expired administrator sessions are deleted automatically.`,
      `Raw payment-provider payloads: ${r.paymentRawEventDays} days; minimum transaction records may be retained for the period required by tax, accounting, refund, and fraud-prevention law.`,
      `Device and license records: while a trial or license is used and until a verified deletion request is completed, except for records that must be retained by law. A one-way anti-abuse tombstone is retained for ${r.tombstoneDays} days after deletion.`,
      `Completed privacy-request records: ${r.deletionRequestDays} days so that we can demonstrate that the request was handled.`,
    ],
    sharingTitle: 'Sharing and international processing',
    sharing: 'Data may be processed by infrastructure, database, email/support, security, and payment providers acting for us. Amazon processes Appstore purchases under its own terms. We disclose data when required by law. We do not allow service providers to use it for their own advertising. Before launch, each production provider and any international transfer safeguard will be recorded in this policy.',
    securityTitle: 'Security',
    security: 'Production traffic uses HTTPS. Device challenges are signed with a key generated on the device. Administrative sessions use secure, HTTP-only cookies. Playlist setup payloads are encrypted at rest while pending. Access is restricted and security events are logged. No system is completely secure, so incidents are handled under an incident-response process.',
    rightsTitle: 'Your rights and deletion',
    rights: (email) => `Depending on your location, you may request access, correction, deletion, restriction, portability, or objection, and may complain to a data-protection authority. A device-data deletion request must be verified using the device's security key so another person cannot erase your license. Until the in-app deletion screen is released, contact ${email} and include only your device code—never send your playlist address or private key. Requests are answered within the period required by applicable law. Some transaction records may be retained where legally required.`,
    childrenTitle: 'Children',
    children: 'The licensing service is not directed to children and we do not knowingly collect children’s personal data. The app does not provide media content; content suitability is controlled by the playlist provider and device owner.',
    changesTitle: 'Changes',
    changes: 'Material changes will be published on this page with a new effective date. The version accepted for a store release will be archived.',
    disclosure: 'Amazon privacy data disclosure',
  },
  de: {
    title: 'Datenschutzerklärung', languageName: 'Deutsch', updated: 'Gültig ab',
    intro: (name) => `${name} stellt eine Media-Player-Anwendung bereit. Wir bieten keine Sender, Filme, Serien oder Abonnements für Mediendienste Dritter an. Nutzer fügen ihre eigene Listenadresse hinzu und sind selbst für die erforderlichen Nutzungsrechte verantwortlich.`,
    controller: 'Verantwortlicher', contact: 'Datenschutzkontakt',
    collectedTitle: 'Verarbeitete Daten',
    collected: [
      ['Geräte- und Lizenzdaten', 'Gerätecode, öffentlicher Geräteschlüssel, Einweg-Gerätebindung, Gerätemodell, Plattform, App-Version, Testzeitraum, Lizenzstatus und letzter Prüfzeitpunkt.'],
      ['Entfernte Listeneinrichtung', 'Vom Nutzer eingegebener Profilname und Listenadresse. Die Daten werden während der kurzen Wartezeit verschlüsselt und nach Abruf durch den TV oder nach Ablauf vom Server gelöscht.'],
      ['Sicherheit und Betrieb', 'IP-Adresse, Anfragezeit, Sicherheitsereignis sowie begrenzte User-Agent- und Sitzungsdaten für Administratoren.'],
      ['Käufe', 'Nach Aktivierung von Käufen: Amazon-Transaktionskennung, Produkt, Preis, Währung, Kaufstatus sowie Erstattungs- oder Rückbuchungsstatus. Zahlungskartendaten werden von Amazon verarbeitet und nicht an uns übermittelt.'],
      ['Daten auf dem Gerät', 'Profile, Favoriten, Einstellungen und Wiedergabeverlauf bleiben auf dem Gerät und werden nicht an den Lizenzdienst übertragen, sofern eine Funktion dies nicht ausdrücklich mitteilt.'],
    ],
    purposesTitle: 'Verarbeitungszwecke', purposes: 'Die Daten werden für den 30-tägigen Testzeitraum, die Gerätebindung und Prüfung von Lizenzen, Kaufwiederherstellung, die vom Nutzer angeforderte Einrichtung, Betrugsabwehr, Sicherheit, Fehlerdiagnose, gesetzliche Pflichten und Datenschutzanfragen verarbeitet. Wir verkaufen keine personenbezogenen Daten und verwenden sie nicht für verhaltensbasierte Werbung.',
    legalTitle: 'Rechtsgrundlagen', legal: 'Soweit die DSGVO gilt, beruht die Verarbeitung auf Vertragserfüllung beziehungsweise vorvertraglichen Maßnahmen, berechtigten Interessen an Sicherheit und Betrugsprävention, gesetzlichen Aufbewahrungspflichten und – sofern gesetzlich erforderlich – Einwilligung.',
    retentionTitle: 'Speicherdauer', retention: (r) => [
      `Listeninhalt: bis zum Abruf durch den TV, höchstens 10 Minuten. Kopplungsmetadaten: ${r.pairingMetadataDays} Tage.`,
      `Lizenz-Challenges: höchstens 24 Stunden. Sicherheits-/Auditdaten: ${r.auditDays} Tage. Abgelaufene Administratorsitzungen werden automatisch gelöscht.`,
      `Rohdaten des Zahlungsanbieters: ${r.paymentRawEventDays} Tage; notwendige Transaktionsdaten für gesetzliche Steuer-, Buchhaltungs-, Erstattungs- und Betrugsfristen.`,
      `Geräte- und Lizenzdaten: während der Nutzung und bis zum Abschluss eines verifizierten Löschantrags, soweit keine gesetzliche Aufbewahrung gilt. Ein nicht umkehrbarer Missbrauchsschutz-Hash bleibt danach ${r.tombstoneDays} Tage gespeichert.`,
      `Abgeschlossene Datenschutzanträge: ${r.deletionRequestDays} Tage als Bearbeitungsnachweis.`,
    ],
    sharingTitle: 'Empfänger und internationale Verarbeitung', sharing: 'Daten können durch unsere Infrastruktur-, Datenbank-, Support-, Sicherheits- und Zahlungsdienstleister verarbeitet werden. Amazon verarbeitet Appstore-Käufe nach eigenen Bedingungen. Eine Offenlegung erfolgt bei gesetzlicher Pflicht. Dienstleister dürfen die Daten nicht für eigene Werbung nutzen. Produktionsanbieter und Schutzmaßnahmen für internationale Übermittlungen werden vor Veröffentlichung ergänzt.',
    securityTitle: 'Sicherheit', security: 'Produktivdaten werden über HTTPS übertragen. Geräteprüfungen werden mit einem auf dem Gerät erzeugten Schlüssel signiert. Administratorsitzungen verwenden sichere HTTP-only-Cookies. Ausstehende Listendaten sind verschlüsselt. Zugriffe sind beschränkt und Sicherheitsereignisse werden protokolliert.',
    rightsTitle: 'Ihre Rechte und Löschung', rights: (email) => `Je nach Wohnort bestehen Rechte auf Auskunft, Berichtigung, Löschung, Einschränkung, Übertragbarkeit und Widerspruch sowie ein Beschwerderecht bei einer Datenschutzbehörde. Löschungen müssen mit dem Geräteschlüssel bestätigt werden, damit niemand fremde Lizenzen löschen kann. Bis die Löschfunktion in der App erscheint, kontaktieren Sie ${email} nur mit dem Gerätecode – niemals mit Listenadresse oder privatem Schlüssel. Gesetzlich erforderliche Transaktionsdaten können weiter gespeichert werden.`,
    childrenTitle: 'Kinder', children: 'Der Lizenzdienst richtet sich nicht an Kinder und erhebt nicht wissentlich deren Daten. Die App stellt keine Medien bereit; für die Eignung der Inhalte sind Listenanbieter und Geräteinhaber verantwortlich.',
    changesTitle: 'Änderungen', changes: 'Wesentliche Änderungen werden mit einem neuen Gültigkeitsdatum auf dieser Seite veröffentlicht. Die zu einer Store-Version gehörende Fassung wird archiviert.',
    disclosure: 'Amazon-Datenschutzauskunft',
  },
  tr: {
    title: 'Gizlilik Politikası', languageName: 'Türkçe', updated: 'Yürürlük tarihi',
    intro: (name) => `${name} bir medya oynatıcı uygulaması sunar. Kanal, film, dizi veya üçüncü taraf yayın aboneliği sağlamayız. Kullanıcı kendi liste adresini ekler ve içerik için gerekli erişim haklarına sahip olmaktan kendisi sorumludur.`,
    controller: 'Veri sorumlusu', contact: 'Gizlilik iletişimi',
    collectedTitle: 'İşlediğimiz veriler',
    collected: [
      ['Cihaz ve lisans verileri', 'Cihaz kodu, cihazın açık anahtarı, tek yönlü cihaz bağı, cihaz modeli, platform, uygulama sürümü, deneme tarihleri, lisans durumu ve son doğrulama zamanı.'],
      ['Telefondan liste kurulumu', 'Kullanıcının yazdığı profil adı ve liste adresi. Veri TV tarafından alınmayı beklerken şifreli tutulur; TV alınca veya süre dolunca liste adresi sunucudan silinir.'],
      ['Güvenlik ve işletim', 'IP adresi, istek zamanı, güvenlik olayı, yöneticiler için sınırlı tarayıcı bilgisi ve oturum kayıtları.'],
      ['Satın almalar', 'Satın alma açıldığında Amazon işlem kimliği, ürün, fiyat, para birimi, satın alma, iade ve ters ibraz durumu. Kart bilgileri Amazon tarafından işlenir ve bize ulaşmaz.'],
      ['Cihazda kalan veriler', 'Profiller, favoriler, ayarlar ve izleme geçmişi cihazda tutulur. Bir özellik açıkça belirtmedikçe lisans sunucusuna gönderilmez.'],
    ],
    purposesTitle: 'Verileri neden işliyoruz', purposes: 'Verileri 30 günlük denemeyi başlatmak ve uygulamak, lisansı doğru cihaza bağlamak, satın almayı geri yüklemek ve doğrulamak, kullanıcının istediği uzaktan kurulumu yapmak, sahtekârlık ve deneme suistimalini önlemek, sistemi korumak, hataları teşhis etmek, yasal yükümlülükleri yerine getirmek ve gizlilik taleplerini yanıtlamak için işleriz. Davranışsal reklam yapmayız ve kişisel veri satmayız.',
    legalTitle: 'Hukuki dayanaklar', legal: 'GDPR uygulandığında işleme; hizmet sözleşmesinin ifası, sözleşme öncesi kullanıcının talep ettiği adımlar, güvenlik ve sahtekârlığı önlemedeki meşru menfaatlerimiz, mali kayıtlar için yasal yükümlülükler ve kanunun özellikle istediği yerde rızaya dayanır.',
    retentionTitle: 'Saklama süreleri', retention: (r) => [
      `Liste verisi: TV alana kadar, en fazla 10 dakika. Eşleştirme metadatası: ${r.pairingMetadataDays} gün.`,
      `Lisans doğrulama istekleri: en fazla 24 saat. Güvenlik/işlem kayıtları: ${r.auditDays} gün. Süresi biten yönetici oturumları otomatik silinir.`,
      `Ödeme sağlayıcısının ham olay verisi: ${r.paymentRawEventDays} gün; zorunlu asgari işlem kayıtları vergi, muhasebe, iade ve sahtekârlık mevzuatının gerektirdiği süre boyunca tutulabilir.`,
      `Cihaz ve lisans kaydı: deneme/lisans kullanılırken ve doğrulanmış silme talebi tamamlanana kadar; yasal tutulması gereken kayıtlar istisnadır. Silme sonrasında tek yönlü suistimal önleme özeti ${r.tombstoneDays} gün tutulur.`,
      `Tamamlanan gizlilik talepleri: talebin yerine getirildiğini kanıtlamak için ${r.deletionRequestDays} gün.`,
    ],
    sharingTitle: 'Paylaşım ve uluslararası işleme', sharing: 'Veriler bizim adımıza çalışan altyapı, veritabanı, destek, güvenlik ve ödeme hizmetlerince işlenebilir. Amazon, Appstore satın almalarını kendi şartlarına göre işler. Kanunen gerektiğinde yetkili mercilerle paylaşırız. Hizmet sağlayıcıların veriyi kendi reklamları için kullanmasına izin vermeyiz. Canlı sistemde seçilen sağlayıcılar ve uluslararası aktarım güvenceleri yayından önce bu politikaya eklenecektir.',
    securityTitle: 'Güvenlik', security: 'Canlı trafik HTTPS kullanır. Cihaz doğrulamaları cihazda üretilen anahtarla imzalanır. Yönetici oturumları güvenli ve HTTP-only çerez kullanır. Bekleyen liste kurulumu verisi şifreli tutulur. Erişim sınırlandırılır ve güvenlik olayları kaydedilir. Hiçbir sistem tamamen güvenli olmadığından olay müdahale süreci uygulanır.',
    rightsTitle: 'Haklarınız ve veri silme', rights: (email) => `Bulunduğunuz yere göre erişim, düzeltme, silme, işlemeyi sınırlama, taşıma ve itiraz haklarınız ile veri koruma makamına şikâyet hakkınız olabilir. Başkasının lisansınızı silememesi için cihaz verisi silme talebi cihazın güvenlik anahtarıyla doğrulanır. Uygulama içi silme ekranı yayınlanana kadar ${email} adresine yalnız cihaz kodunuzla başvurun; liste adresinizi veya özel anahtarınızı asla göndermeyin. Talepler yürürlükteki kanunun süresi içinde yanıtlanır. Yasal zorunluluk bulunan işlem kayıtları saklanabilir.`,
    childrenTitle: 'Çocuklar', children: 'Lisans hizmeti çocuklara yönelik değildir ve bilerek çocuklara ait kişisel veri toplamayız. Uygulama medya içeriği sağlamaz; içeriğin uygunluğunu liste sağlayıcısı ve cihaz sahibi kontrol eder.',
    changesTitle: 'Değişiklikler', changes: 'Önemli değişiklikler yeni yürürlük tarihiyle bu sayfada yayınlanır. Her mağaza sürümünde kabul edilen politika sürümü arşivlenir.',
    disclosure: 'Amazon gizlilik veri beyanı',
  },
};

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[character]));
}

export function resolvePrivacyLanguage(requested, acceptLanguage = '') {
  const candidate = String(requested || acceptLanguage).slice(0, 2).toLowerCase();
  return Object.hasOwn(policies, candidate) ? candidate : 'en';
}

export function renderPrivacyPage({ language, controllerName, contactEmail, effectiveDate, retention }) {
  const strings = policies[language] ?? policies.en;
  const section = (title, body) => `<section><h2>${escapeHtml(title)}</h2>${body}</section>`;
  const list = (items) => `<ul>${items.map((item) => `<li>${escapeHtml(item)}</li>`).join('')}</ul>`;
  const dataList = `<dl>${strings.collected.map(([term, description]) => `<div><dt>${escapeHtml(term)}</dt><dd>${escapeHtml(description)}</dd></div>`).join('')}</dl>`;
  return `<!doctype html><html lang="${language}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>TIVUQIPTV — ${escapeHtml(strings.title)}</title><style>${privacyCss}</style></head><body><main><nav><strong>TIVUQIPTV</strong><span><a href="?lang=en">EN</a><a href="?lang=de">DE</a><a href="?lang=tr">TR</a></span></nav><header><p>PRIVACY</p><h1>${escapeHtml(strings.title)}</h1><p>${escapeHtml(strings.updated)}: ${escapeHtml(effectiveDate)}</p></header><article><p class="lead">${escapeHtml(strings.intro(controllerName))}</p><div class="controller"><div><b>${escapeHtml(strings.controller)}</b><span>${escapeHtml(controllerName)}</span></div><div><b>${escapeHtml(strings.contact)}</b><a href="mailto:${escapeHtml(contactEmail)}">${escapeHtml(contactEmail)}</a></div></div>${section(strings.collectedTitle, dataList)}${section(strings.purposesTitle, `<p>${escapeHtml(strings.purposes)}</p>`)}${section(strings.legalTitle, `<p>${escapeHtml(strings.legal)}</p>`)}${section(strings.retentionTitle, list(strings.retention(retention)))}${section(strings.sharingTitle, `<p>${escapeHtml(strings.sharing)}</p>`)}${section(strings.securityTitle, `<p>${escapeHtml(strings.security)}</p>`)}${section(strings.rightsTitle, `<p>${escapeHtml(strings.rights(contactEmail))}</p>`)}${section(strings.childrenTitle, `<p>${escapeHtml(strings.children)}</p>`)}${section(strings.changesTitle, `<p>${escapeHtml(strings.changes)}</p>`)}<p class="foot"><a href="/privacy/data-disclosure.json">${escapeHtml(strings.disclosure)}</a></p></article></main></body></html>`;
}

export function privacyDisclosure(config) {
  return {
    schemaVersion: 1,
    effectiveDate: config.privacyEffectiveDate,
    controller: { name: config.privacyControllerName, contactEmail: config.privacyContactEmail },
    appRole: 'user-provided-media-player',
    providesMediaContent: false,
    sellsPersonalData: false,
    behavioralAdvertising: false,
    data: [
      { category: 'device_identifiers', collected: true, purposes: ['app_functionality', 'fraud_prevention', 'security'], linkedToDevice: true },
      { category: 'purchase_history', collected: true, purposes: ['purchase_fulfillment', 'refunds', 'fraud_prevention'], linkedToDevice: true, paymentCardDataReceived: false },
      { category: 'user_content_profile_name', collected: true, purposes: ['remote_setup'], transient: true },
      { category: 'user_content_playlist_url', collected: true, purposes: ['remote_setup'], encryptedAtRestWhilePending: true, maximumPendingMinutes: 10 },
      { category: 'app_activity_watch_history', collectedByBackend: false, storedOnDevice: true },
      { category: 'diagnostics_and_security', collected: true, purposes: ['security', 'support'], retentionDays: config.auditRetentionDays },
      { category: 'precise_location', collected: false },
      { category: 'contacts', collected: false },
      { category: 'advertising_id', collected: false },
    ],
    deletion: { verifiedDeviceRequestSupportedByApi: true, contactEmail: config.privacyContactEmail },
  };
}

const privacyCss = `:root{color-scheme:dark;font-family:Inter,ui-sans-serif,system-ui,sans-serif;background:#090812;color:#f6f4ff}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 80% 0,#1b1540 0,#090812 36%);line-height:1.65}main{width:min(940px,calc(100% - 32px));margin:auto;padding:24px 0 70px}nav{display:flex;justify-content:space-between;align-items:center;padding:10px 0 34px}nav span{display:flex;gap:8px}a{color:#aaa4ff}nav a{padding:7px 10px;text-decoration:none;border:1px solid #ffffff15;border-radius:9px}header{padding:38px;border:1px solid #ffffff14;border-radius:24px;background:#151123}header p{color:#aaa4ff;margin:0;font-size:13px}h1{font-size:clamp(34px,6vw,58px);margin:6px 0 12px;line-height:1.05}article{padding:12px 38px}.lead{font-size:18px;color:#d8d4e8}.controller{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:28px 0}.controller div{display:grid;padding:18px;background:#151123;border:1px solid #ffffff12;border-radius:14px}.controller b,dt{color:#fff}.controller span,.controller a,dd{color:#aaa5bc}section{padding:25px 0;border-top:1px solid #ffffff12}h2{font-size:22px;margin:0 0 12px}p,li,dd{color:#b8b2ca}li{margin:8px 0}dl{display:grid;gap:12px}dl div{padding:17px;background:#12101c;border-radius:12px}dt{font-weight:800}dd{margin:5px 0 0}.foot{text-align:center;padding-top:25px}@media(max-width:640px){header,article{padding-left:20px;padding-right:20px}.controller{grid-template-columns:1fr}}`;
