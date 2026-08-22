import 'package:flutter/widgets.dart';

class AppStrings {
  const AppStrings(this.languageCode);

  final String languageCode;

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('de'),
    Locale('tr'),
  ];

  static Locale resolveLocale(Locale? deviceLocale) {
    final languageCode = deviceLocale?.languageCode.toLowerCase();
    return supportedLocales.firstWhere(
      (locale) => locale.languageCode == languageCode,
      orElse: () => const Locale('en'),
    );
  }

  static AppStrings of(BuildContext context) {
    return AppStrings(Localizations.localeOf(context).languageCode);
  }

  T _value<T>({required T en, required T de, required T tr}) {
    return switch (languageCode) {
      'de' => de,
      'tr' => tr,
      _ => en,
    };
  }

  String trialTitle(int days) => _value(
        en: 'Try TIVUQIPTV free\nfor $days days',
        de: 'TIVUQIPTV $days Tage\nkostenlos testen',
        tr: 'TIVUQIPTV’yi $days gün\nücretsiz deneyin',
      );

  String trialDescription(int days) => _value(
        en: 'Your trial starts today. After $days days, a one-time license linked '
            'to this device is required to continue using the app.',
        de: 'Ihre Testphase beginnt heute. Nach $days Tagen benötigen Sie eine '
            'einmalig bezahlte, mit diesem Gerät verknüpfte Lizenz.',
        tr: 'Deneme süreniz bugün başlar. $days günün sonunda uygulamayı '
            'kullanmaya devam etmek için bu cihaza bağlı, tek seferlik ücretli '
            'lisans satın almanız gerekir.',
      );

  String trialEndDate(String date) => _value(
        en: 'Trial ends: $date',
        de: 'Ende der Testphase: $date',
        tr: 'Deneme bitiş tarihi: $date',
      );

  String get deviceCode => _value(
        en: 'DEVICE CODE',
        de: 'GERÄTECODE',
        tr: 'CİHAZ KODU',
      );

  String get starting => _value(
        en: 'Starting…',
        de: 'Wird gestartet…',
        tr: 'Başlatılıyor…',
      );

  String get startFreeTrial => _value(
        en: 'Start Free Trial',
        de: 'Kostenlose Testphase starten',
        tr: 'Ücretsiz Denemeyi Başlat',
      );

  String freeDaysBadge(int days) => _value(
        en: '$days DAYS FREE',
        de: '$days TAGE KOSTENLOS',
        tr: '$days GÜN ÜCRETSİZ',
      );

  String get licenseAndPaymentLink => _value(
        en: 'License and payment link',
        de: 'Lizenz- und Zahlungslink',
        tr: 'Lisans ve ödeme bağlantısı',
      );

  String get paymentAddressPending => _value(
        en: 'The payment address will be added before launch',
        de: 'Die Zahlungsadresse wird vor dem Start hinzugefügt',
        tr: 'Ödeme adresi satıştan önce eklenecek',
      );

  String buyBeforeTrialEnds(int days) => _value(
        en: 'You may also purchase a license before the $days-day trial ends.',
        de: 'Sie können die Lizenz auch vor Ablauf der $days-tägigen Testphase kaufen.',
        tr: '$days gün dolmadan da lisans satın alabilirsiniz.',
      );

  String get amazonPurchaseTitle => _value(
        en: 'Purchase through Amazon Appstore',
        de: 'Kauf über den Amazon Appstore',
        tr: 'Amazon Appstore Üzerinden Satın Alın',
      );

  String amazonPurchaseDescription(int days) => _value(
        en: 'After the $days-day free trial, the one-time license is purchased '
            'securely through Amazon Appstore.',
        de: 'Nach der $days-tägigen kostenlosen Testphase wird die einmalige '
            'Lizenz sicher über den Amazon Appstore gekauft.',
        tr: '$days günlük ücretsiz denemeden sonra tek seferlik lisans güvenli '
            'şekilde Amazon Appstore üzerinden satın alınır.',
      );

  String get amazonProcessesPurchases => _value(
        en: 'Purchases and receipts are processed by Amazon.',
        de: 'Käufe und Belege werden von Amazon verarbeitet.',
        tr: 'Satın alma ve makbuz işlemleri Amazon tarafından gerçekleştirilir.',
      );

  String get addChannelsWithPhone => _value(
        en: 'Add your channels with your phone',
        de: 'Sender mit dem Smartphone hinzufügen',
        tr: 'Kanallarınızı Telefonla Ekleyin',
      );

  String get scanChannelSetupQr => _value(
        en: 'Scan the QR code and enter your personal playlist address. It will '
            'be added to this TV automatically.',
        de: 'Scannen Sie den QR-Code und geben Sie Ihre persönliche Listenadresse '
            'ein. Sie wird automatisch zu diesem TV hinzugefügt.',
        tr: 'QR kodu okutun ve kişisel liste adresinizi girin. Listeniz bu TV’ye '
            'otomatik olarak eklenecek.',
      );

  String get pairingCodePreparing => _value(
        en: 'Preparing a secure setup code…',
        de: 'Sicherer Einrichtungscode wird vorbereitet…',
        tr: 'Güvenli kurulum kodu hazırlanıyor…',
      );

  String get pairingCodeExpired => _value(
        en: 'The setup code expired.',
        de: 'Der Einrichtungscode ist abgelaufen.',
        tr: 'Kurulum kodunun süresi doldu.',
      );

  String get pairingUnavailable => _value(
        en: 'Channel setup is temporarily unavailable.',
        de: 'Die Sendereinrichtung ist vorübergehend nicht verfügbar.',
        tr: 'Kanal kurulumu geçici olarak kullanılamıyor.',
      );

  String get retry =>
      _value(en: 'Retry', de: 'Erneut versuchen', tr: 'Tekrar Dene');

  String get playlistAdded => _value(
        en: 'Your channel list was added successfully.',
        de: 'Ihre Senderliste wurde erfolgreich hinzugefügt.',
        tr: 'Kanal listeniz başarıyla eklendi.',
      );

  String get playlistTransferredSecurely => _value(
        en: 'The temporary transfer data was removed from the server.',
        de: 'Die temporären Übertragungsdaten wurden vom Server entfernt.',
        tr: 'Geçici aktarım bilgileri sunucudan silindi.',
      );

  String get oneTimeSecureCode => _value(
        en: 'The code is valid for 10 minutes and can only be used once.',
        de: 'Der Code ist 10 Minuten gültig und kann nur einmal verwendet werden.',
        tr: 'Kod 10 dakika geçerlidir ve yalnızca bir kez kullanılabilir.',
      );

  String get licenseVerificationFailed => _value(
        en: 'The license could not be verified.',
        de: 'Die Lizenz konnte nicht überprüft werden.',
        tr: 'Lisans doğrulanamadı.',
      );

  String get trialExpired => _value(
        en: 'TRIAL EXPIRED',
        de: 'TESTPHASE ABGELAUFEN',
        tr: 'DENEME SÜRESİ DOLDU',
      );

  String get activateToContinue => _value(
        en: 'Activate this device\nto continue using\nthe app.',
        de: 'Aktivieren Sie dieses Gerät,\num die App weiter\nzu verwenden.',
        tr: 'Uygulamayı kullanmaya\ndevam etmek için cihazınızı\naktifleştirin.',
      );

  String get yourDeviceCode => _value(
        en: 'Your TIVUQIPTV device code:',
        de: 'Ihr TIVUQIPTV-Gerätecode:',
        tr: 'TIVUQIPTV Cihaz Kodunuz:',
      );

  String get deviceCodeExplanation => _value(
        en: 'This code is generated from the device security key. Visit our '
            'website to activate a license for this device.',
        de: 'Dieser Code wird aus dem Sicherheitsschlüssel des Geräts erzeugt. '
            'Besuchen Sie unsere Website, um dieses Gerät zu lizenzieren.',
        tr: 'Bu kod cihazın güvenli anahtarından üretilir. Bu cihaz için lisans '
            'açmak üzere web sitemizi ziyaret edin.',
      );

  String get checking => _value(
        en: 'Checking…',
        de: 'Wird überprüft…',
        tr: 'Kontrol Ediliyor…',
      );

  String get checkLicense => _value(
        en: 'Check License',
        de: 'Lizenz prüfen',
        tr: 'Lisansı Kontrol Et',
      );

  String get scanWithPhone => _value(
        en: 'Scan with your phone',
        de: 'Mit dem Smartphone scannen',
        tr: 'Telefonunuzla okutun',
      );

  String get activationAddressMissing => _value(
        en: 'Activation address is not configured',
        de: 'Aktivierungsadresse ist nicht konfiguriert',
        tr: 'Aktivasyon adresi yapılandırılmamış',
      );

  String get amazonDeviceCodeExplanation => _value(
        en: 'This code securely identifies your Fire TV during license verification.',
        de: 'Dieser Code identifiziert Ihren Fire TV sicher bei der Lizenzprüfung.',
        tr: 'Bu kod, lisans doğrulaması sırasında Fire TV’nizi güvenli şekilde tanımlar.',
      );
}
