import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/user_selection_screen.dart';
import 'screens/live_tv_screen.dart';
import 'screens/movies_screen.dart';
import 'screens/series_screen.dart';
import 'screens/video_player_screen.dart';
import 'theme/app_colors.dart';
import 'providers/settings_provider.dart';
import 'providers/channel_provider.dart';
import 'providers/watch_history_provider.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'models/profile.dart';
import 'screens/splash_screen.dart';
import 'l10n/app_strings.dart';
import 'services/local_companion_service.dart';
import 'services/player_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('Media Kit initialization failed: $e');
  }

  // Hata durumunda beyaz ekran kalmaması için global hata yakalayıcı
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exception}');
  };

  final settingsProvider = SettingsProvider();
  final watchHistoryProvider = WatchHistoryProvider();
  final channelProvider = ChannelProvider();
  LocalCompanionService(
    settingsProvider,
    channelProvider,
    watchHistoryProvider,
  ).initialize();

  // runApp önce çağrılır — splash ekranı ANINDA görünür, donma olmaz
  // Provider init işlemleri splash içinde arka planda yapılır
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: watchHistoryProvider),
        ChangeNotifierProvider.value(value: channelProvider),
      ],
      child: IPTVApp(
        settingsProvider: settingsProvider,
        watchHistoryProvider: watchHistoryProvider,
      ),
    ),
  );
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class IPTVApp extends StatefulWidget {
  final SettingsProvider settingsProvider;
  final WatchHistoryProvider watchHistoryProvider;
  const IPTVApp({
    super.key,
    required this.settingsProvider,
    required this.watchHistoryProvider,
  });

  @override
  State<IPTVApp> createState() => _IPTVAppState();
}

class _IPTVAppState extends State<IPTVApp> {
  int _handledContentSequence = 0;
  int _handledChannelSequence = 0;
  int _remoteNavigationGeneration = 0;

  @override
  void initState() {
    super.initState();
    LocalCompanionService.contentPlayRequest.addListener(_openPhoneContent);
    LocalCompanionService.channelPlayRequest.addListener(_openPhoneChannel);
  }

  @override
  void dispose() {
    LocalCompanionService.contentPlayRequest.removeListener(_openPhoneContent);
    LocalCompanionService.channelPlayRequest.removeListener(_openPhoneChannel);
    super.dispose();
  }

  Profile? _profileForRemoteContent(LocalContentPlayRequest request) {
    final profiles = widget.settingsProvider.profiles;
    final sourceProfileId = request.item.sourceProfileId;
    for (final profile in profiles) {
      if (profile.id == sourceProfileId) return profile;
    }
    final lastProfileId = widget.settingsProvider.lastProfileId;
    for (final profile in profiles) {
      if (profile.id == lastProfileId) return profile;
    }
    return profiles.firstOrNull;
  }

  void _openPhoneContent() {
    final request = LocalCompanionService.contentPlayRequest.value;
    if (request == null || request.sequence == _handledContentSequence) return;
    _handledContentSequence = request.sequence;
    LocalCompanionService.liveTvTransitionInProgress = false;
    final generation = ++_remoteNavigationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = appNavigatorKey.currentState;
      final profile = _profileForRemoteContent(request);
      if (navigator == null || profile == null) return;
      final targetScreen =
          request.section == LocalContentSection.series ? 'series' : 'movies';
      final sectionWasAlreadyOpen =
          widget.settingsProvider.lastScreen == targetScreen &&
              LocalCompanionService.vodPlaybackDepth.value == 0;
      await widget.settingsProvider.setLastState(
        screen: targetScreen,
        profileId: profile.id,
      );
      if (!mounted || generation != _remoteNavigationGeneration) return;

      if (!sectionWasAlreadyOpen) {
        final section = request.section == LocalContentSection.series
            ? SeriesScreen(profile: profile)
            : MoviesScreen(profile: profile);
        navigator.pushAndRemoveUntil<void>(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => section,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
          (_) => false,
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || generation != _remoteNavigationGeneration) return;
      }

      await navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            url: request.item.url,
            title: request.item.name,
            profileId: request.item.sourceProfileId ?? '',
            httpHeaders: request.item.httpHeaders,
            playlist: request.playlist,
            initialIndex: request.initialIndex,
            historyGroupId: request.seriesId,
            historyGroupItemCount: request.playlist?.length,
          ),
        ),
      );
      if (generation == _remoteNavigationGeneration) {
        LocalCompanionService.contentPlaybackClosed.value++;
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _openPhoneChannel() {
    final request = LocalCompanionService.channelPlayRequest.value;
    if (request == null || request.sequence == _handledChannelSequence) return;
    _handledChannelSequence = request.sequence;

    // Canlı TV zaten öndeyse kanal değişimini mevcut ekran kendi kesintisiz
    // akışı içinde uygular. VOD veya başka bir katalog açıksa gezinme katmanı
    // önce canlı TV'ye geçirilir.
    if (widget.settingsProvider.lastScreen == 'live_tv' &&
        LocalCompanionService.vodPlaybackDepth.value == 0) {
      return;
    }

    final generation = ++_remoteNavigationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = appNavigatorKey.currentState;
      if (navigator == null) return;
      LocalCompanionService.liveTvTransitionInProgress =
          LocalCompanionService.vodPlaybackDepth.value > 0;
      await widget.settingsProvider.setLastState(screen: 'live_tv');
      if (!mounted || generation != _remoteNavigationGeneration) return;
      await AppPlayerEngine.prepareLiveDisplayModeAndWait(
        refreshRate: widget.settingsProvider.liveTvRefreshRate,
      );
      if (!mounted || generation != _remoteNavigationGeneration) return;

      // Native ExoPlayer event channels are process-wide. Building LiveTVScreen
      // before the VOD adapter has fully disposed lets the old subscription's
      // delayed onCancel clear the new live player's event sink. The channel
      // then plays, but Dart misses READY and performs an unnecessary timeout
      // fallback that briefly replaces the video surface.
      if (LocalCompanionService.vodPlaybackDepth.value > 0) {
        navigator.pushAndRemoveUntil<void>(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const _RemoteLiveTvHandoffScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
          (_) => false,
        );
        await _waitForVodPlaybackToClose();
        if (!mounted || generation != _remoteNavigationGeneration) return;
        navigator.pushReplacement<void, void>(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => LiveTVScreen(
              initialRemoteChannelId: request.id,
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        return;
      }

      navigator.pushAndRemoveUntil<void>(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => LiveTVScreen(
            initialRemoteChannelId: request.id,
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (_) => false,
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _waitForVodPlaybackToClose() async {
    if (LocalCompanionService.vodPlaybackDepth.value == 0) return;
    final completer = Completer<void>();
    void handleDepthChanged() {
      if (LocalCompanionService.vodPlaybackDepth.value == 0 &&
          !completer.isCompleted) {
        completer.complete();
      }
    }

    LocalCompanionService.vodPlaybackDepth.addListener(handleDepthChanged);
    try {
      await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      debugPrint('VOD olay bağlantısının kapanması zaman aşımına uğradı.');
    } finally {
      LocalCompanionService.vodPlaybackDepth.removeListener(handleDepthChanged);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'TIVUQIPTV',
          debugShowCheckedModeBanner: false,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (deviceLocale, supportedLocales) =>
              AppStrings.resolveLocale(deviceLocale),
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: AppColors.backgroundLight,
            colorScheme: ColorScheme.fromSeed(
              seedColor: settings.primaryColor,
              primary: settings.primaryColor,
              brightness: Brightness.dark,
            ),
            textTheme: GoogleFonts.notoSansTextTheme(),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: AppColors.backgroundDark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: settings.primaryColor,
              primary: settings.primaryColor,
              brightness: Brightness.dark,
              surface: AppColors.surfaceDark,
            ),
            textTheme: GoogleFonts.notoSansTextTheme(
              ThemeData.dark().textTheme,
            ),
          ),
          themeMode: ThemeMode.dark,
          builder: (context, child) => Stack(
            fit: StackFit.expand,
            children: [
              child ?? const SizedBox.shrink(),
              ValueListenableBuilder<LocalPairingPrompt?>(
                valueListenable: LocalCompanionService.pairingPrompt,
                builder: (context, prompt, _) {
                  if (prompt == null) return const SizedBox.shrink();
                  return _PairingCodeOverlay(prompt: prompt);
                },
              ),
            ],
          ),
          home: SplashScreen(
            settingsProvider: widget.settingsProvider,
            watchHistoryProvider: widget.watchHistoryProvider,
          ),
        );
      },
    );
  }
}

class _RemoteLiveTvHandoffScreen extends StatelessWidget {
  const _RemoteLiveTvHandoffScreen();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

class _PairingCodeOverlay extends StatelessWidget {
  const _PairingCodeOverlay({required this.prompt});

  final LocalPairingPrompt prompt;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final title = language == 'tr'
        ? 'Telefon eşleştirme kodu'
        : language == 'de'
            ? 'Telefon-Kopplungscode'
            : 'Phone pairing code';
    final helper = language == 'tr'
        ? 'Bu kodu TIVUQIPTV Remote’a girin'
        : language == 'de'
            ? 'Diesen Code in TIVUQIPTV Remote eingeben'
            : 'Enter this code in TIVUQIPTV Remote';

    return Positioned(
      right: 20,
      bottom: 20,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 270,
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
            decoration: BoxDecoration(
              color: const Color(0xF2171424),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 18),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.phonelink_lock_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  prompt.code,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 28,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  helper,
                  style: const TextStyle(color: Colors.white70, fontSize: 9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RootWrapper extends StatefulWidget {
  const RootWrapper({super.key});

  @override
  State<RootWrapper> createState() => _RootWrapperState();
}

class _RootWrapperState extends State<RootWrapper> {
  Future<void>? _loadPlaylistFuture;
  String? _loadedProfilesKey;

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    // Ayarlar henüz yüklenmediyse (Main'de await ediyoruz ama ek güvenlik)
    if (!settings.isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0B),
        body: Center(child: CircularProgressIndicator(color: Colors.blue)),
      );
    }

    // Eğer profil listesi boşsa direkt kullanıcı seçimine/ekleme ekranına git
    if (settings.profiles.isEmpty) {
      return const UserSelectionScreen();
    }

    // Son kullanılan profil id'sini kontrol et
    final lastProfileId = settings.lastProfileId;
    Profile? currentProfile;

    if (lastProfileId != null) {
      try {
        currentProfile = settings.profiles.firstWhere(
          (p) => p.id == lastProfileId,
        );
      } catch (_) {
        currentProfile = null;
      }
    }

    // Kullanıcı ekranı artık yönetim içindir; tüm profiller aynı anda aktiftir.
    // Geçerli bir son profil yoksa ilk profil yalnızca arayüz bağlamı olur.
    if (currentProfile == null && settings.profiles.isNotEmpty) {
      currentProfile = settings.profiles.first;
      // Auto-save the last profile id so next launch loads immediately without checking
      settings.setLastState(profileId: currentProfile.id, screen: 'home');
    }

    // Profil bulunamadıysa seçim ekranına dön.
    if (currentProfile == null) {
      return const UserSelectionScreen();
    }

    final profilesKey = settings.profiles
        .map((profile) => '${profile.id}:${profile.m3uUrl ?? ''}')
        .join('|');
    // Tüm kullanıcı listeleri tek katalog olarak atomik biçimde yüklenir.
    if (_loadedProfilesKey != profilesKey) {
      final channelProvider = Provider.of<ChannelProvider>(
        context,
        listen: false,
      );
      _loadedProfilesKey = profilesKey;
      _loadPlaylistFuture = Future.microtask(
        () => channelProvider.loadProfiles(settings.profiles),
      );
    }

    Widget targetScreen;
    if (settings.startupScreen == 'live_tv') {
      targetScreen = const LiveTVScreen();
    } else if (settings.startupScreen == 'movies') {
      targetScreen = MoviesScreen(profile: currentProfile);
    } else if (settings.startupScreen == 'series') {
      targetScreen = SeriesScreen(profile: currentProfile);
    } else if (settings.startupScreen == 'last_screen') {
      if (settings.lastScreen == 'movies') {
        targetScreen = MoviesScreen(profile: currentProfile);
      } else if (settings.lastScreen == 'series') {
        targetScreen = SeriesScreen(profile: currentProfile);
      } else {
        targetScreen = const LiveTVScreen();
      }
    } else {
      targetScreen = const LiveTVScreen();
    }

    // Live TV can start from the persisted last channel while the full merged
    // catalogue is restored in the background. Waiting here used to add a
    // second 5-10 second logo screen on every launch.
    if (targetScreen is LiveTVScreen) {
      unawaited(_loadPlaylistFuture ?? Future<void>.value());
      return targetScreen;
    }

    return FutureBuilder<void>(
      future: _loadPlaylistFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreenBody();
        }

        final channelProvider = Provider.of<ChannelProvider>(
          context,
          listen: false,
        );
        if (channelProvider.error != null) {
          return Scaffold(
            backgroundColor: const Color(0xFF131022),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 64,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Oynatma Listesi Yüklenemedi',
                      style: GoogleFonts.splineSans(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      channelProvider.error!,
                      style: const TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _loadedProfilesKey = null; // force reload
                            });
                          },
                          child: const Text('Tekrar Dene'),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton(
                          onPressed: () {
                            settings.setLastState(
                              clearProfile: true,
                              screen: 'user_selection',
                            );
                            setState(() {
                              _loadedProfilesKey = null;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white30),
                          ),
                          child: const Text('Kullanıcı Değiştir'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return targetScreen;
      },
    );
  }
}
