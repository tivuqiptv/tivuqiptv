import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';

class SettingsProvider extends ChangeNotifier {
  static final SettingsProvider _instance = SettingsProvider._internal();
  factory SettingsProvider() => _instance;
  SettingsProvider._internal();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _profilesSecureKey = 'profiles_secure_v1';
  static const String _favoritesSecureKey = 'favorites_secure_v1';
  static const String _parentalPinsSecureKey = 'parental_pins_secure_v1';
  static const String _parentalLocksSecureKey = 'parental_locks_secure_v1';
  static const MethodChannel _autoLaunchChannel = MethodChannel(
    'com.tivuq.iptv/auto_launch',
  );
  static const bool _desktopVisualPreview = bool.fromEnvironment(
    'DESKTOP_VISUAL_PREVIEW',
  );

  Color _primaryColor = const Color(0xFF2196F3); // Default Blue
  double _sidebarOpacity = 0.1; // Default 10%
  double _autoHideDuration = 3.0;
  String _language = 'en';
  String _quality = 'auto'; // Default Auto
  String _startupScreen = 'live_tv'; // live_tv, movies, series, last_screen
  String _lastScreen = 'user_selection';
  String? _lastProfileId;
  List<Profile> _profiles = [];
  bool _isInitialized = false;
  String _preferredEngine =
      'legacy'; // Stable default; Media3 remains optional.
  String _vodPreferredEngine = 'legacy';
  bool _showDiagnostics = false;
  bool _enableTunneling = false;
  bool _autoStartOnBoot = false;
  int _liveTvRefreshRate = 50;
  String? _lastWatchedChannelUrl;
  final Set<String> _favoriteKeys = <String>{};
  final Map<String, String> _parentalPinDigests = <String, String>{};
  final Set<String> _parentalLockKeys = <String>{};
  int _companionSettingsRevision = 0;
  int _catalogVisibilityRevision = 0;
  int _catalogMembershipRevision = 0;

  // Getters
  bool get isInitialized => _isInitialized;
  Color get primaryColor => _primaryColor;
  double get sidebarOpacity => _sidebarOpacity;
  double get autoHideDuration => _autoHideDuration;
  String get language => _language;
  String get quality => _quality;
  String get startupScreen => _startupScreen;
  String get lastScreen => _lastScreen;
  String? get lastProfileId => _lastProfileId;
  List<Profile> get profiles => List.unmodifiable(_profiles);
  String get preferredEngine => _preferredEngine;
  String get vodPreferredEngine => _vodPreferredEngine;
  bool get showDiagnostics => _showDiagnostics;
  bool get enableTunneling => _enableTunneling;
  bool get autoStartOnBoot => _autoStartOnBoot;
  int get liveTvRefreshRate => _liveTvRefreshRate;
  String? get lastWatchedChannelUrl => _lastWatchedChannelUrl;
  int get companionSettingsRevision => _companionSettingsRevision;
  int get catalogVisibilityRevision => _catalogVisibilityRevision;
  int get catalogMembershipRevision => _catalogMembershipRevision;

  bool isFavorite(String type, String contentId, {String? profileId}) {
    return _favoriteKeys.contains(
      _favoriteKey(type, contentId, profileId: profileId),
    );
  }

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      final colorHex = prefs.getString('primaryColor');
      if (colorHex != null) {
        try {
          _primaryColor = Color(int.parse(colorHex, radix: 16));
        } catch (e) {
          debugPrint('Renk ayrıştırma hatası: $e');
        }
      }

      _sidebarOpacity = prefs.getDouble('sidebarOpacity') ?? 0.1;
      double? savedDuration;
      try {
        savedDuration = prefs.getDouble('autoHideDuration');
      } catch (_) {
        savedDuration = prefs.getInt('autoHideDuration')?.toDouble();
      }
      _autoHideDuration = savedDuration ?? 3.0;

      if (prefs.containsKey('language')) {
        _language = prefs.getString('language')!;
      } else {
        // Detect device locale
        try {
          final locale = WidgetsBinding.instance.platformDispatcher.locale;
          final String languageCode = locale.languageCode.toLowerCase();
          final String countryCode = locale.countryCode?.toLowerCase() ?? '';

          if (languageCode == 'tr' || countryCode == 'tr') {
            _language = 'tr';
          } else if (languageCode == 'de' || countryCode == 'de') {
            _language = 'de';
          } else {
            _language = 'en';
          }
        } catch (e) {
          _language = 'en';
        }
      }

      var savedEngine = prefs.getString('preferredEngine') ?? 'legacy';
      // Media3 was accidentally made the default for new installs even though
      // the migration plan keeps Legacy as the safe Fire TV fallback. Repair
      // that rollout once; an explicit Media3 choice made afterwards persists.
      const stableEngineMigrationKey = 'stable_live_engine_migration_v1';
      if (prefs.getBool(stableEngineMigrationKey) != true) {
        if (savedEngine == 'fireTvMedia3') {
          savedEngine = 'legacy';
          await prefs.setString('preferredEngine', savedEngine);
        }
        await prefs.setBool(stableEngineMigrationKey, true);
      }
      // VLC is never a Live TV engine. Migrate an old VLC choice to VOD only.
      _preferredEngine = savedEngine == 'vlc' ? 'legacy' : savedEngine;
      _vodPreferredEngine = prefs.getString('vodPreferredEngine') ??
          (savedEngine == 'vlc' ? 'vlc' : 'legacy');
      _showDiagnostics = prefs.getBool('showDiagnostics') ?? false;
      _enableTunneling = prefs.getBool('enableTunneling') ?? false;
      _autoStartOnBoot = prefs.getBool('autoStartOnBoot') ?? false;
      _liveTvRefreshRate = prefs.getInt('liveTvRefreshRate') == 60 ? 60 : 50;
      // Boot receiver configuration is not needed before the first frame.
      unawaited(_configureAutoLaunchService(_autoStartOnBoot));
      _quality = prefs.getString('quality') ?? 'auto';
      _startupScreen = prefs.getString('startupScreen') ?? 'live_tv';
      _lastScreen = prefs.getString('lastScreen') ?? 'user_selection';
      _lastProfileId = prefs.getString('lastProfileId');
      _lastWatchedChannelUrl = prefs.getString('lastWatchedChannelUrl');

      String? profilesJson = prefs.getString('profiles_recovery');
      try {
        profilesJson ??= await _secureStorage.read(key: _profilesSecureKey);
      } catch (error) {
        debugPrint('Güvenli profil deposu okunamadı: ${error.runtimeType}');
      }

      // Eski sürümde SharedPreferences içinde tutulan profilleri güvenli alana taşı.
      profilesJson ??= prefs.getString('profiles');
      if (profilesJson != null) {
        final List<dynamic> decoded = jsonDecode(profilesJson);
        _profiles = decoded.map((p) => Profile.fromMap(p)).toList();
        unawaited(_finishProfileStorageMigration(prefs, profilesJson));
      }

      // Masaüstü görsel önizleme her çalıştırmada gerçek bir ilk kurulum gibi
      // başlar. Diskteki geliştirme profilleri silinmez ve üretim derlemesinde
      // bu dal kDebugMode nedeniyle tamamen kapalıdır.
      if (kDebugMode && _desktopVisualPreview) {
        _profiles = [];
        _lastProfileId = null;
      }

      try {
        final favoritesJson = prefs.getString('favorites_recovery') ??
            await _secureStorage.read(key: _favoritesSecureKey);
        if (favoritesJson != null) {
          final decoded = jsonDecode(favoritesJson);
          if (decoded is List) {
            _favoriteKeys
              ..clear()
              ..addAll(decoded.whereType<String>());
          }
        }
      } catch (error) {
        debugPrint('Favoriler güvenli depodan okunamadı: ${error.runtimeType}');
      }

      try {
        final pinsJson = await _secureStorage.read(key: _parentalPinsSecureKey);
        if (pinsJson != null) {
          final decoded = jsonDecode(pinsJson);
          if (decoded is Map) {
            _parentalPinDigests
              ..clear()
              ..addAll(
                decoded.map(
                  (key, value) => MapEntry(key.toString(), value.toString()),
                ),
              );
          }
        }
        final locksJson = await _secureStorage.read(
          key: _parentalLocksSecureKey,
        );
        if (locksJson != null) {
          final decoded = jsonDecode(locksJson);
          if (decoded is List) {
            _parentalLockKeys
              ..clear()
              ..addAll(decoded.whereType<String>());
          }
        }
      } catch (error) {
        debugPrint(
          'Ebeveyn kontrolü güvenli depodan okunamadı: ${error.runtimeType}',
        );
      }

      _isInitialized = true;
      _companionSettingsRevision++;
      _catalogVisibilityRevision++;
      notifyListeners();
    } catch (e) {
      debugPrint('Settings init hatası: $e');
      // Hata olsa bile initialized sayalım ki loop olmasın veya hatalı kalsın
      _isInitialized = true;
      _companionSettingsRevision++;
      _catalogVisibilityRevision++;
      notifyListeners();
    }
  }

  Future<void> _finishProfileStorageMigration(
    SharedPreferences prefs,
    String profilesJson,
  ) async {
    try {
      await _secureStorage.write(
        key: _profilesSecureKey,
        value: profilesJson,
      );
      await prefs.remove('profiles');
      await prefs.remove('profiles_recovery');
    } catch (error) {
      debugPrint('Profil güvenli depoya taşınamadı: ${error.runtimeType}');
    }
  }

  // Setters
  Future<void> updateSettings({
    Color? primaryColor,
    double? sidebarOpacity,
    double? autoHideDuration,
    String? language,
    String? quality,
    String? startupScreen,
    String? preferredEngine,
    String? vodPreferredEngine,
    bool? showDiagnostics,
    bool? enableTunneling,
    bool? autoStartOnBoot,
    int? liveTvRefreshRate,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (preferredEngine != null) {
      _preferredEngine = preferredEngine == 'vlc' ? 'legacy' : preferredEngine;
      await prefs.setString('preferredEngine', _preferredEngine);
    }
    if (vodPreferredEngine != null) {
      _vodPreferredEngine = vodPreferredEngine;
      await prefs.setString('vodPreferredEngine', vodPreferredEngine);
    }
    if (showDiagnostics != null) {
      _showDiagnostics = showDiagnostics;
      await prefs.setBool('showDiagnostics', showDiagnostics);
    }
    if (enableTunneling != null) {
      _enableTunneling = enableTunneling;
      await prefs.setBool('enableTunneling', enableTunneling);
    }
    if (autoStartOnBoot != null) {
      _autoStartOnBoot = autoStartOnBoot;
      await prefs.setBool('autoStartOnBoot', autoStartOnBoot);
      await _configureAutoLaunchService(autoStartOnBoot);
    }
    if (liveTvRefreshRate != null) {
      _liveTvRefreshRate = liveTvRefreshRate == 60 ? 60 : 50;
      await prefs.setInt('liveTvRefreshRate', _liveTvRefreshRate);
    }

    if (primaryColor != null) {
      _primaryColor = primaryColor;
      await prefs.setString(
        'primaryColor',
        primaryColor.toARGB32().toRadixString(16),
      );
    }
    if (sidebarOpacity != null) {
      _sidebarOpacity = sidebarOpacity;
      await prefs.setDouble('sidebarOpacity', sidebarOpacity);
    }
    if (autoHideDuration != null) {
      _autoHideDuration = autoHideDuration;
      await prefs.setDouble('autoHideDuration', autoHideDuration);
    }
    if (language != null) {
      _language = language;
      await prefs.setString('language', language);
    }
    if (quality != null) {
      _quality = quality;
      await prefs.setString('quality', quality);
    }
    if (startupScreen != null) {
      _startupScreen = startupScreen;
      await prefs.setString('startupScreen', startupScreen);
    }

    _companionSettingsRevision++;
    notifyListeners();
  }

  Future<void> _configureAutoLaunchService(bool enabled) async {
    try {
      await _autoLaunchChannel.invokeMethod<void>('configure', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Android dışındaki platformlarda bu hizmet bulunmaz.
    } on PlatformException catch (error) {
      debugPrint(
        'Otomatik başlatma hizmeti ayarlanamadı: ${error.runtimeType}',
      );
    }
  }

  Future<void> setLastState({
    String? screen,
    String? profileId,
    bool clearProfile = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (screen != null) {
      _lastScreen = screen;
      await prefs.setString('lastScreen', screen);
    }
    if (clearProfile) {
      _lastProfileId = null;
      await prefs.remove('lastProfileId');
    } else if (profileId != null) {
      _lastProfileId = profileId;
      await prefs.setString('lastProfileId', profileId);
    }
    notifyListeners();
  }

  Future<void> setLastWatchedChannelUrl(String url) async {
    _lastWatchedChannelUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastWatchedChannelUrl', url);
    notifyListeners();
  }

  Future<void> saveProfile(Profile profile) async {
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index != -1) {
      _profiles[index] = profile;
    } else {
      _profiles.add(profile);
    }
    notifyListeners();
    await _persistProfiles();
  }

  Future<void> deleteProfile(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    _favoriteKeys.removeWhere((key) => key.startsWith('$id|'));
    _parentalPinDigests.remove(id);
    _parentalLockKeys.removeWhere((key) => key.startsWith('$id|'));
    if (_lastProfileId == id) {
      _lastProfileId = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lastProfileId');
    }
    notifyListeners();
    await Future.wait([
      _persistProfiles(),
      _persistFavorites(),
      _persistParentalControls(),
    ]);
  }

  Future<void> _persistProfiles() async {
    final String encoded = jsonEncode(_profiles.map((p) => p.toMap()).toList());
    try {
      await _secureStorage.write(key: _profilesSecureKey, value: encoded);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('profiles_recovery');
    } catch (error) {
      // Eski Fire OS sürümlerinde Keystore geçici olarak açılamazsa veri kaybını
      // önle; güvenli depo tekrar çalıştığında init bu kaydı otomatik taşır.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profiles_recovery', encoded);
      debugPrint('Profil güvenli depoya yazılamadı: ${error.runtimeType}');
    }
  }

  Future<bool> toggleFavorite(
    String type,
    String contentId, {
    String? profileId,
  }) async {
    final key = _favoriteKey(type, contentId, profileId: profileId);
    final isNowFavorite = !_favoriteKeys.remove(key);
    if (isNowFavorite) _favoriteKeys.add(key);
    _catalogMembershipRevision++;
    notifyListeners();
    await _persistFavorites();
    return isNowFavorite;
  }

  String _favoriteKey(String type, String contentId, {String? profileId}) {
    final owner = profileId ?? _lastProfileId ?? 'global';
    return '$owner|$type|$contentId';
  }

  Future<void> _persistFavorites() async {
    final encoded = jsonEncode(_favoriteKeys.toList()..sort());
    try {
      await _secureStorage.write(key: _favoritesSecureKey, value: encoded);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('favorites_recovery');
    } catch (error) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('favorites_recovery', encoded);
      debugPrint('Favoriler güvenli depoya yazılamadı: ${error.runtimeType}');
    }
  }

  String _parentalOwner([String? profileId]) =>
      profileId ?? _lastProfileId ?? 'global';

  bool hasParentalPin({String? profileId}) =>
      _parentalPinDigests.containsKey(_parentalOwner(profileId));

  bool isCategoryLocked(String type, String category, {String? profileId}) {
    return _parentalLockKeys.contains(
      _parentalLockKey(type, category, profileId: profileId),
    );
  }

  bool isCategoryHidden(String type, String category, {String? profileId}) =>
      isCategoryLocked(type, category, profileId: profileId);

  List<({String type, String category})> hiddenCategories({String? profileId}) {
    final owner = _parentalOwner(profileId);
    final prefix = '$owner|';
    final result = <({String type, String category})>[];
    for (final key in _parentalLockKeys) {
      if (!key.startsWith(prefix)) continue;
      final remainder = key.substring(prefix.length);
      final separator = remainder.indexOf('|');
      if (separator <= 0 || separator >= remainder.length - 1) continue;
      try {
        result.add((
          type: remainder.substring(0, separator),
          category: utf8.decode(
            base64Url.decode(
              base64Url.normalize(remainder.substring(separator + 1)),
            ),
          ),
        ));
      } catch (_) {
        // Ignore malformed legacy entries instead of breaking settings.
      }
    }
    result.sort((a, b) {
      final typeOrder = a.type.compareTo(b.type);
      return typeOrder != 0
          ? typeOrder
          : a.category.toLowerCase().compareTo(b.category.toLowerCase());
    });
    return result;
  }

  Future<bool> setParentalPin(String pin, {String? profileId}) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) return false;
    final random = Random.secure();
    final salt = base64UrlEncode(
      List<int>.generate(18, (_) => random.nextInt(256)),
    );
    final digest = sha256.convert(utf8.encode('$salt:$pin')).toString();
    final owner = _parentalOwner(profileId);
    final previous = _parentalPinDigests[owner];
    _parentalPinDigests[owner] = '$salt:$digest';
    try {
      await _persistParentalControls();
    } catch (_) {
      if (previous == null) {
        _parentalPinDigests.remove(owner);
      } else {
        _parentalPinDigests[owner] = previous;
      }
      return false;
    }
    notifyListeners();
    return true;
  }

  bool verifyParentalPin(String pin, {String? profileId}) {
    final stored = _parentalPinDigests[_parentalOwner(profileId)];
    if (stored == null) return false;
    final separator = stored.indexOf(':');
    if (separator <= 0 || separator >= stored.length - 1) return false;
    final salt = stored.substring(0, separator);
    final expected = stored.substring(separator + 1);
    final actual = sha256.convert(utf8.encode('$salt:$pin')).toString();
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<void> setCategoryLocked(
    String type,
    String category,
    bool locked, {
    String? profileId,
  }) async {
    final key = _parentalLockKey(type, category, profileId: profileId);
    final wasLocked = _parentalLockKeys.contains(key);
    if (locked) {
      _parentalLockKeys.add(key);
    } else {
      _parentalLockKeys.remove(key);
    }
    try {
      await _persistParentalControls();
    } catch (_) {
      if (wasLocked) {
        _parentalLockKeys.add(key);
      } else {
        _parentalLockKeys.remove(key);
      }
      rethrow;
    }
    _catalogVisibilityRevision++;
    notifyListeners();
  }

  Future<void> setCategoryHidden(
    String type,
    String category,
    bool hidden, {
    String? profileId,
  }) =>
      setCategoryLocked(type, category, hidden, profileId: profileId);

  Future<void> clearParentalControl({String? profileId}) async {
    final owner = _parentalOwner(profileId);
    final previousPin = _parentalPinDigests.remove(owner);
    final previousLocks = _parentalLockKeys
        .where((key) => key.startsWith('$owner|'))
        .toList(growable: false);
    _parentalLockKeys.removeWhere((key) => key.startsWith('$owner|'));
    try {
      await _persistParentalControls();
    } catch (_) {
      if (previousPin != null) _parentalPinDigests[owner] = previousPin;
      _parentalLockKeys.addAll(previousLocks);
      rethrow;
    }
    _catalogVisibilityRevision++;
    notifyListeners();
  }

  String _parentalLockKey(String type, String category, {String? profileId}) {
    final owner = _parentalOwner(profileId);
    final encodedCategory = base64UrlEncode(utf8.encode(category));
    return '$owner|$type|$encodedCategory';
  }

  Future<void> _persistParentalControls() async {
    try {
      await Future.wait([
        _secureStorage.write(
          key: _parentalPinsSecureKey,
          value: jsonEncode(_parentalPinDigests),
        ),
        _secureStorage.write(
          key: _parentalLocksSecureKey,
          value: jsonEncode(_parentalLockKeys.toList()..sort()),
        ),
      ]);
    } catch (error) {
      debugPrint(
        'Ebeveyn kontrolü güvenli depoya yazılamadı: ${error.runtimeType}',
      );
      rethrow;
    }
  }

  // Localization logic
  String getText(String key, [Map<String, String>? params]) {
    return getTranslatedText(key, _language, params);
  }

  String getTranslatedText(
    String key,
    String lang, [
    Map<String, String>? params,
  ]) {
    final Map<String, Map<String, String>> translations = {
      'tr': {
        'settings': 'Ayarlar',
        'appearance': 'Görünüm',
        'sidebar_opacity': 'Sidebar Opaklığı',
        'auto_hide': 'Otomatik Gizleme',
        'seconds': 'Saniye',
        'off': 'Kapalı',
        'language_quality': 'Dil & Kalite',
        'language': 'Uygulama Dili',
        'video_quality': 'Video Kalitesi',
        'save_changes': 'Değişiklikleri Kaydet',
        'live_tv': 'Canlı TV',
        'movies': 'Filmler',
        'series': 'Diziler',
        'search_hint': 'Ara...',
        'search_movie': 'Film Ara...',
        'search_series': 'Dizi Ara...',
        'movie_list': 'Film Listesi',
        'series_list': 'Dizi Listesi',
        'added_to_favorites': '{name} favorilere eklendi',
        'removed_from_favorites': '{name} favorilerden çıkarıldı',
        'all': 'Tümü',
        'favorites_cat': 'Favoriler',
        'no_channel_found': 'Kanal bulunamadı',
        'stream_unavailable': 'Yayın açılamadı',
        'recent_channels': 'Son İzlenen Kanallar',
        'recently_watched': 'Son İzlenenler',
        'no_recent_channels': 'Henüz izlenen kanal yok',
        'no_content_found': 'İçerik bulunamadı',
        'premium_membership': 'Premium Üyelik',
        'live_broadcast': 'Canlı Yayın',
        'system_settings': 'SİSTEM AYARLARI',
        'player_prefs': 'Oynatıcı Tercihleri',
        'opacity_label': 'Sidebar Opaklığı',
        'autohide_label': 'Otomatik Gizleme Süresi',
        'lang_selection': 'Dil Seçimi',
        'icon_colors': 'Simgelerin Rengi',
        'save': 'KAYDET',
        'cancel': 'VAZGEÇ',
        'live_preview': 'Canlı Önizleme',
        'color_description': 'Seçtiğiniz renk menüde böyle görünecek.',
        'welcome': 'Hoş Geldiniz',
        'select_category': 'Lütfen devam etmek için bir kategori seçin',
        'watch_now': 'HEMEN İZLE',
        'more_info': 'Daha Fazla Bilgi',
        'episodes': 'Bölümler',
        'add_to_favorites': 'Favorilere Ekle',
        'in_favorites': 'Favorilerde',
        'premium_status': 'PREMIUM ÜST DÜZEY',
        'ultra_hd': 'ULTRA HD',
        'new_release': 'YENİ YAYIN',
        'who_watching': 'Kim izliyor?',
        'tr_dubbed': 'Türkçe Dublaj',
        'subtitled': 'Altyazılı',
        'local_cinema': 'Yerli Sinema',
        'hollywood': 'Hollywood',
        'european_cinema': 'Avrupa Sineması',
        'documentaries': 'Belgeseller',
        'kids_movies': 'Çocuk Filmleri',
        'popular_series': 'Popüler Diziler',
        'auto': 'Otomatik',
        'auto_desc': 'Hıza göre ayarla',
        'quality_4k': '4K Ultra HD',
        'quality_1080p': '1080p Full HD',
        'quality_720p': '720p Standart',
        'newly_added': 'Yeni Eklenenler',
        'sci_fi_fantasy': 'Bilim Kurgu & Fantastik',
        'drama': 'Dram',
        'action_adventure': 'Aksiyon & Macera',
        'comedy': 'Komedi',
        'doc_series': 'Belgesel Diziler',
        'turkey': 'Türkiye',
        'sports': 'Spor',
        'cinema': 'Sinema',
        'news': 'Haber',
        'music': 'Müzik',
        'startup_screen': 'Başlangıç Ekranı',
        'user_selection': 'Kullanıcı Seçimi',
        'last_screen': 'Kaldığım Yer',
        'auto_start_on_boot': 'TV açıldığında otomatik başlat',
        'auto_start_on_boot_desc':
            'Fire TV açıldığında veya uykudan uyandığında TIVUQIPTV açılır',
        'live_tv_refresh_rate': 'Canlı TV Yenileme Hızı',
        'live_tv_refresh_50_desc': 'Türkiye ve Avrupa kanalları için önerilen',
        'live_tv_refresh_60_desc': 'Amerika ve Kanada kanalları için önerilen',
        'auto_save': 'Otomatik Kayıt Aktif',
        'close': 'Kapat',
      },
      'en': {
        'settings': 'Settings',
        'appearance': 'Appearance',
        'sidebar_opacity': 'Sidebar Opacity',
        'auto_hide': 'Auto Hide',
        'seconds': 'Seconds',
        'off': 'Off',
        'language_quality': 'Language & Quality',
        'language': 'App Language',
        'video_quality': 'Video Quality',
        'save_changes': 'Save Changes',
        'live_tv': 'Live TV',
        'movies': 'Movies',
        'series': 'Series',
        'search_hint': 'Search...',
        'search_movie': 'Search Movies...',
        'search_series': 'Search Series...',
        'movie_list': 'Movie List',
        'series_list': 'Series List',
        'added_to_favorites': '{name} added to favorites',
        'removed_from_favorites': '{name} removed from favorites',
        'all': 'All',
        'favorites_cat': 'Favorites',
        'no_channel_found': 'No channel found',
        'stream_unavailable': 'Stream could not be opened',
        'recent_channels': 'Recently Watched',
        'recently_watched': 'Recently Watched',
        'no_recent_channels': 'No watched channels yet',
        'no_content_found': 'No content found',
        'premium_membership': 'Premium Membership',
        'live_broadcast': 'Live Broadcast',
        'system_settings': 'SYSTEM SETTINGS',
        'player_prefs': 'Player Preferences',
        'opacity_label': 'Sidebar Opacity',
        'autohide_label': 'Auto-Hide Duration',
        'lang_selection': 'Language Selection',
        'icon_colors': 'Icon Colors',
        'save': 'SAVE',
        'cancel': 'CANCEL',
        'live_preview': 'Live Preview',
        'color_description': 'Your icon will look like this.',
        'welcome': 'Welcome',
        'select_category': 'Please select a category to continue',
        'watch_now': 'WATCH NOW',
        'more_info': 'More Info',
        'episodes': 'Episodes',
        'add_to_favorites': 'Add to Favorites',
        'in_favorites': 'In Favorites',
        'premium_status': 'PREMIUM TIER',
        'ultra_hd': 'ULTRA HD',
        'new_release': 'NEW RELEASE',
        'who_watching': 'Who\'s watching?',
        'tr_dubbed': 'Turkish Dubbed',
        'subtitled': 'Subtitled',
        'local_cinema': 'Local Cinema',
        'hollywood': 'Hollywood',
        'european_cinema': 'European Cinema',
        'documentaries': 'Documentaries',
        'kids_movies': 'Kids Movies',
        'popular_series': 'Popular Series',
        'auto': 'Automatic',
        'auto_desc': 'Adjust by speed',
        'quality_4k': '4K Ultra HD',
        'quality_1080p': '1080p Full HD',
        'quality_720p': '720p Standard',
        'newly_added': 'Newly Added',
        'sci_fi_fantasy': 'Sci-Fi & Fantasy',
        'drama': 'Drama',
        'action_adventure': 'Action & Adventure',
        'comedy': 'Comedy',
        'doc_series': 'Documentary Series',
        'turkey': 'Turkey',
        'sports': 'Sports',
        'cinema': 'Cinema',
        'news': 'News',
        'music': 'Music',
        'startup_screen': 'Startup Screen',
        'user_selection': 'User Selection',
        'last_screen': 'Keep Last Stage',
        'auto_start_on_boot': 'Launch when TV starts',
        'auto_start_on_boot_desc':
            'Opens TIVUQIPTV when Fire TV starts or wakes from sleep',
        'live_tv_refresh_rate': 'Live TV Refresh Rate',
        'live_tv_refresh_50_desc': 'Recommended for Türkiye and Europe',
        'live_tv_refresh_60_desc': 'Recommended for the USA and Canada',
        'auto_save': 'Auto-Save Active',
        'close': 'Close',
      },
      'de': {
        'settings': 'Einstellungen',
        'appearance': 'Aussehen',
        'sidebar_opacity': 'Sidebar-Deckkraft',
        'auto_hide': 'Auto-Ausblenden',
        'seconds': 'Sekunden',
        'off': 'Aus',
        'language_quality': 'Sprache & Qualität',
        'language': 'App-Sprache',
        'video_quality': 'Videoqualität',
        'save_changes': 'Änderungen speichern',
        'live_tv': 'Live TV',
        'movies': 'Filme',
        'series': 'Serien',
        'search_hint': 'Suchen...',
        'search_movie': 'Filme suchen...',
        'search_series': 'Serien suchen...',
        'movie_list': 'Filmliste',
        'series_list': 'Serienliste',
        'added_to_favorites': '{name} zu Favoriten hinzugefügt',
        'removed_from_favorites': '{name} aus Favoriten entfernt',
        'all': 'Alle',
        'favorites_cat': 'Favoriten',
        'no_channel_found': 'Kein Kanal gefunden',
        'stream_unavailable': 'Stream konnte nicht geöffnet werden',
        'recent_channels': 'Zuletzt gesehen',
        'recently_watched': 'Zuletzt angesehen',
        'no_recent_channels': 'Noch keine Sender angesehen',
        'no_content_found': 'Kein Inhalt gefunden',
        'premium_membership': 'Premium-Mitgliedschaft',
        'live_broadcast': 'Live-Übertragung',
        'system_settings': 'SYSTEMEINSTELLUNGEN',
        'player_prefs': 'Player-Einstellungen',
        'opacity_label': 'Sidebar-Deckkraft',
        'autohide_label': 'Auto-Ausblendzeit',
        'lang_selection': 'Sprachauswahl',
        'icon_colors': 'Symbolfarben',
        'save': 'SPEICHERN',
        'cancel': 'ABBRECHEN',
        'live_preview': 'Live-Vorschau',
        'color_description': 'Ihre Symbole werden so aussehen.',
        'welcome': 'Willkommen',
        'select_category': 'Bitte wählen Sie eine Kategorie, um fortzufahren',
        'watch_now': 'JETZT ANSEHEN',
        'more_info': 'Mehr Info',
        'episodes': 'Episoden',
        'add_to_favorites': 'Zu Favoriten hinzufügen',
        'in_favorites': 'In Favoriten',
        'premium_status': 'PREMIUM-STUFE',
        'ultra_hd': 'ULTRA HD',
        'new_release': 'NEUHEIT',
        'who_watching': 'Wer schaut zu?',
        'tr_dubbed': 'Türkisch synchronisiert',
        'subtitled': 'Untertitel',
        'local_cinema': 'Lokales Kino',
        'hollywood': 'Hollywood',
        'european_cinema': 'Europäisches Kino',
        'documentaries': 'Dokumentationen',
        'kids_movies': 'Kinderfilme',
        'popular_series': 'Beliebte Serien',
        'auto': 'Automatisch',
        'auto_desc': 'Nach Geschwindigkeit',
        'quality_4k': '4K Ultra HD',
        'quality_1080p': '1080p Full HD',
        'quality_720p': '720p Standard',
        'newly_added': 'Neu hinzugefügt',
        'sci_fi_fantasy': 'Sci-Fi & Fantasy',
        'drama': 'Drama',
        'action_adventure': 'Action & Abenteuer',
        'comedy': 'Komödie',
        'doc_series': 'Dokumentarserien',
        'turkey': 'Türkei',
        'sports': 'Sport',
        'cinema': 'Kino',
        'news': 'Nachrichten',
        'music': 'Musik',
        'startup_screen': 'Startbildschirm',
        'user_selection': 'Benutzerauswahl',
        'last_screen': 'Letzer Stand',
        'auto_start_on_boot': 'Beim TV-Start automatisch öffnen',
        'auto_start_on_boot_desc':
            'Öffnet TIVUQIPTV beim Start oder Aufwachen von Fire TV',
        'live_tv_refresh_rate': 'Live-TV-Bildwiederholrate',
        'live_tv_refresh_50_desc': 'Empfohlen für die Türkei und Europa',
        'live_tv_refresh_60_desc': 'Empfohlen für die USA und Kanada',
        'auto_save': 'Auto-Speichern Aktiv',
        'close': 'Schließen',
      },
    };

    String text = translations[lang]?[key] ?? translations['en']?[key] ?? key;
    if (params != null) {
      params.forEach((k, v) {
        text = text.replaceAll('{$k}', v);
      });
    }
    return text;
  }
}
