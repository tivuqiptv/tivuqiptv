import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/services/playlist_service.dart';

void main() {
  group('M3U parser', () {
    test('canlı yayın, film ve diziyi ayırır', () {
      const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="news" tvg-logo="https://img/news.png" group-title="Haber Kanalları",Haber TV
http://stream.example/live/user/pass/1.ts
#EXTINF:-1 group-title="Filmler",Örnek Film (2025)
https://stream.example/movie/user/pass/2.mkv
#EXTINF:-1 group-title="Diziler",Örnek Dizi S02E03
https://stream.example/series/user/pass/3.mp4
''';

      final channels = PlaylistService().parseM3U(playlist);

      expect(channels, hasLength(3));
      expect(channels[0].id, 'news');
      expect(channels[0].isLive, isTrue);
      expect(channels[1].isLive, isFalse);
      expect(channels[2].isLive, isFalse);
      expect(channels[0].category, 'Haber Kanalları');
    });

    test('tvg-id yoksa aynı içerik için kararlı kimlik üretir', () {
      const playlist = '''
#EXTM3U
#EXTINF:-1 group-title="Spor",Spor TV
http://stream.example/live/10.ts
''';

      final first = PlaylistService().parseM3U(playlist).single;
      final second = PlaylistService().parseM3U(playlist).single;

      expect(first.id, second.id);
      expect(first.id, startsWith('channel_'));
    });

    test('geçersiz satırları kanal olarak eklemez', () {
      const playlist = '#EXTM3U\n#EXTVLCOPT:http-user-agent=test\n';
      expect(PlaylistService().parseM3U(playlist), isEmpty);
    });

    test('kanala özel HTTP başlıklarını korur', () {
      const playlist = '''
#EXTM3U
#EXTINF:-1 group-title="Spor",Korunan Kanal
#EXTVLCOPT:http-user-agent=ChannelAgent/1.0
#EXTVLCOPT:http-referrer=https://portal.example/
#EXTHTTP:{"Origin":"https://portal.example"}
https://stream.example/live/20.m3u8|Cookie=session%3Dabc
''';

      final channel = PlaylistService().parseM3U(playlist).single;

      expect(channel.url, 'https://stream.example/live/20.m3u8');
      expect(channel.httpHeaders, {
        'User-Agent': 'ChannelAgent/1.0',
        'Referer': 'https://portal.example/',
        'Origin': 'https://portal.example',
        'Cookie': 'session=abc',
      });
    });

    test('sinema grubundaki HLS canlı kanalını VOD olarak sınıflandırmaz', () {
      const playlist = '''
#EXTM3U
#EXTINF:-1 group-title="Sinema Kanalları",Sinema TV
https://stream.example/channel/sinema.m3u8
#EXTINF:-1 group-title="Sinema Filmleri",Örnek Film
https://stream.example/movie/user/pass/42.mp4
''';

      final channels = PlaylistService().parseM3U(playlist);

      expect(channels, hasLength(2));
      expect(channels[0].isLive, isTrue);
      expect(channels[1].isLive, isFalse);
    });

    test('M3U yedeğinde HLS dizi ile 7/24 sinema kanalını ayırır', () {
      const playlist = '''
#EXTM3U
#EXTINF:-1 group-title="Diziler",Örnek Dizi S01E01
https://stream.example/content/episode-1.m3u8
#EXTINF:-1 group-title="Sinema",7/24 Aksiyon
https://stream.example/content/action.m3u8
#EXTINF:-1 group-title="Filmler",Örnek Film
https://stream.example/content/movie.m3u8
''';

      final channels = PlaylistService().parseM3U(playlist);

      expect(channels[0].isLive, isFalse);
      expect(channels[1].isLive, isTrue);
      expect(channels[2].isLive, isFalse);
    });

    test('M3U eklenme tarihini saniye ve ISO biçiminde okur', () {
      const playlist = '''
#EXTM3U
#EXTINF:-1 group-title="Filmler" added="1735689600",Zamanlı Film
https://stream.example/movie/user/pass/51.mp4
#EXTINF:-1 group-title="Diziler" date-added="2025-02-03T10:15:00Z",Zamanlı Dizi S01E01
https://stream.example/series/user/pass/52.mp4
''';

      final channels = PlaylistService().parseM3U(playlist);

      expect(channels[0].addedAt, DateTime.utc(2025, 1, 1));
      expect(channels[1].addedAt, DateTime.utc(2025, 2, 3, 10, 15));
    });
  });
}
