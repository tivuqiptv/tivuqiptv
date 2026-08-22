import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/providers/watch_history_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('son izlenenleri profile göre ayırır ve zamana göre sıralar', () async {
    final history = WatchHistoryProvider();
    await history.init();

    await history.saveProgress(
      'film-a',
      10,
      100,
      profileId: 'profil-1',
      watchedAt: DateTime.utc(2026, 1, 1),
    );
    await history.saveProgress(
      'film-b',
      20,
      100,
      profileId: 'profil-1',
      watchedAt: DateTime.utc(2026, 1, 2),
    );
    await history.saveProgress(
      'film-c',
      30,
      100,
      profileId: 'profil-2',
      watchedAt: DateTime.utc(2026, 1, 3),
    );

    expect(history.recentlyWatchedIds('profil-1'), ['film-b', 'film-a']);
    expect(history.recentlyWatchedIds('profil-2'), ['film-c']);
  });

  test('eski global geçmiş yeni profil son izlenenlerine karışmaz', () async {
    SharedPreferences.setMockInitialValues({
      'hist_pos_eski-film': 15,
      'hist_dur_eski-film': 100,
    });
    final history = WatchHistoryProvider();
    await history.init();

    expect(history.getProgress('eski-film')?.position, 15);
    expect(history.recentlyWatchedIds('yeni-profil'), isEmpty);
  });

  test('oynatma başlarken süre bilinmese de son izlenenlere ekler', () async {
    final history = WatchHistoryProvider();
    await history.init();

    await history.markWatched(
      'telefon-filmi',
      profileId: 'profil-1',
      watchedAt: DateTime.utc(2026, 2, 3),
    );

    expect(history.recentlyWatchedIds('profil-1'), ['telefon-filmi']);
    expect(
      history.getLastWatchedAt('telefon-filmi', profileId: 'profil-1'),
      DateTime.utc(2026, 2, 3),
    );
  });
}
