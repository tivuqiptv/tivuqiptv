import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/l10n/app_strings.dart';

void main() {
  test('desteklenen cihaz dili doğrudan seçilir', () {
    expect(
        AppStrings.resolveLocale(const Locale('de', 'DE')).languageCode, 'de');
    expect(
        AppStrings.resolveLocale(const Locale('tr', 'TR')).languageCode, 'tr');
  });

  test('desteklenmeyen cihaz dili İngilizceye düşer', () {
    expect(
        AppStrings.resolveLocale(const Locale('fr', 'FR')).languageCode, 'en');
    expect(AppStrings.resolveLocale(null).languageCode, 'en');
  });

  test('ücretsiz deneme butonunda gün sayısı bulunmaz', () {
    for (final locale in AppStrings.supportedLocales) {
      final text = AppStrings(locale.languageCode).startFreeTrial;
      expect(text, isNot(contains('30')));
      expect(text, isNot(contains('90')));
    }
  });
}
