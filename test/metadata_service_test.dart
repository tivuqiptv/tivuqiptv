import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/services/metadata_service.dart';

void main() {
  test('başlıktaki ülke, kalite ve yıl etiketlerini temizler', () {
    expect(
      MetadataService.cleanTitle('TR: Örnek Film (2024) [1080p] WEB-DL'),
      'Örnek Film',
    );
  });
}
