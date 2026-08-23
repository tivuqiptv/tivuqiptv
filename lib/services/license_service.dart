import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

enum LicenseStatus { active, trial, expired }

class LicenseService {
  static const _storage = FlutterSecureStorage();
  static const _identityChannel = MethodChannel(
    'com.tivuq.iptv/device_identity',
  );
  static const _legacyDeviceIdKey = 'device_id';
  static const _trialStartKey = 'trial_start_date';
  static const _licenseStatusKey = 'license_status';
  static const _licenseTokenKey = 'license_token_v1';
  static const _lastVerifiedKey = 'license_last_verified';
  static const _trialIntroductionKey = 'trial_introduction_v1_completed';

  static const String licenseApiBaseUrl = String.fromEnvironment(
    'LICENSE_API_BASE_URL',
  );
  static const String activationBaseUrl = String.fromEnvironment(
    'ACTIVATION_URL',
  );
  static const String phoneAppDownloadUrl = String.fromEnvironment(
    'PHONE_APP_DOWNLOAD_URL',
  );
  static const String licenseServerPublicKey = String.fromEnvironment(
    'LICENSE_SERVER_PUBLIC_KEY',
  );
  static const bool enforceServerLicense = bool.fromEnvironment(
    'ENFORCE_SERVER_LICENSE',
  );
  static const bool _desktopVisualPreview = bool.fromEnvironment(
    'DESKTOP_VISUAL_PREVIEW',
  );
  static const String _developerSigningCertificateSha256 =
      '196E2F041F59E9058220DBBE8187D349D41710DD35348571D43A85C096D3ACF7';
  static const String _storeSigningCertificates = String.fromEnvironment(
    'OFFICIAL_SIGNING_CERT_SHA256',
  );

  static const int trialDays = 30;

  static String? _deviceId;
  static String? _devicePublicKey;
  static String? _deviceModel;
  static String? _deviceBinding;
  static bool _secureDeviceIdentity = false;
  static bool _officialAppSignature = false;
  static LicenseStatus _status = LicenseStatus.expired;
  static DateTime? _trialStart;
  static DateTime? _serverTrialExpiresAt;
  static bool _trialIntroductionCompleted = false;
  static String? _lastError;

  static String get deviceId => _deviceId ?? 'UNKNOWN';
  static LicenseStatus get status => _status;
  static String? get lastError => _lastError;
  static bool get hasSecureDeviceIdentity => _secureDeviceIdentity;
  static bool get isDesktopVisualPreview => kDebugMode && _desktopVisualPreview;
  static bool get trialIntroductionCompleted => _trialIntroductionCompleted;
  static bool get isActivationConfigured =>
      licenseApiBaseUrl.trim().isNotEmpty &&
      activationBaseUrl.trim().isNotEmpty &&
      licenseServerPublicKey.trim().isNotEmpty;

  static Uri? get activationUri {
    final base = Uri.tryParse(activationBaseUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;
    return base.replace(
      queryParameters: <String, String>{
        ...base.queryParameters,
        'deviceCode': deviceId,
      },
    );
  }

  static Uri? get phoneAppDownloadUri {
    final uri = Uri.tryParse(phoneAppDownloadUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  static int get trialDaysRemaining {
    final expires = trialExpiresAt;
    if (expires == null) return 0;
    final remaining = expires.toUtc().difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) return 0;
    return (remaining.inSeconds / Duration.secondsPerDay).ceil();
  }

  static int calculateTrialDaysRemaining(DateTime startedAt, {DateTime? now}) {
    final expires = startedAt.toUtc().add(const Duration(days: trialDays));
    final remaining = expires.difference((now ?? DateTime.now()).toUtc());
    if (remaining <= Duration.zero) return 0;
    return (remaining.inSeconds / Duration.secondsPerDay).ceil();
  }

  static DateTime? get trialExpiresAt =>
      _serverTrialExpiresAt ??
      _trialStart?.add(const Duration(days: trialDays));

  static Future<void> init() async {
    _lastError = null;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      await _loadDeviceIdentity();
      _status = LicenseStatus.active;
      _trialIntroductionCompleted = true;
      _lastError = null;
      return;
    }
    if (kDebugMode && _desktopVisualPreview) {
      _deviceId = 'DESKTOP-PREVIEW';
      _trialStart = DateTime.now().toUtc();
      _status = LicenseStatus.trial;
      _trialIntroductionCompleted = false;
      return;
    }
    try {
      await _loadDeviceIdentity();
      _trialIntroductionCompleted =
          await _storage.read(key: _trialIntroductionKey) == 'true';

      final cachedToken = await _storage.read(key: _licenseTokenKey);
      final cachedStatus =
          cachedToken == null ? null : await _validateLicenseToken(cachedToken);
      if (cachedStatus != null) {
        _status = cachedStatus;
        if (licenseApiBaseUrl.isNotEmpty) {
          // The cached token is signed, device-bound and expiry-checked above.
          // Do not hold the TV splash screen on a network round trip; refresh
          // it silently after playback has already started.
          unawaited(refreshStatus(silent: true));
        }
        return;
      }

      // Eski, imzasız aktif kayıtlar ticari protokolde geçerli kabul edilmez.
      await _storage.delete(key: _licenseStatusKey);
      await _storage.delete(key: _licenseTokenKey);

      if (enforceServerLicense) {
        if (!isActivationConfigured) {
          _status = LicenseStatus.expired;
          _lastError = 'Üretim lisans sunucusu yapılandırılmamış.';
          return;
        }
        await refreshStatus(silent: true);
        return;
      }

      final trialStartText = await _storage.read(key: _trialStartKey);
      if (trialStartText == null) {
        _trialStart = DateTime.now().toUtc();
        await _storage.write(
          key: _trialStartKey,
          value: _trialStart!.toIso8601String(),
        );
        _status = LicenseStatus.trial;
        return;
      }

      _trialStart = DateTime.tryParse(trialStartText)?.toUtc();
      if (_trialStart == null) {
        _status = LicenseStatus.expired;
        _lastError = 'Deneme bilgisi geçersiz.';
        return;
      }
      final expires = _trialStart!.add(const Duration(days: trialDays));
      _status = DateTime.now().toUtc().isBefore(expires)
          ? LicenseStatus.trial
          : LicenseStatus.expired;
    } catch (error) {
      _deviceId ??= _generateLegacyDeviceId();
      _status = LicenseStatus.expired;
      _lastError =
          'Güvenli lisans deposuna erişilemedi (${error.runtimeType}).';
    }
  }

  static Future<void> completeTrialIntroduction() async {
    if (kDebugMode && _desktopVisualPreview) {
      _trialIntroductionCompleted = true;
      return;
    }
    await _storage.write(key: _trialIntroductionKey, value: 'true');
    _trialIntroductionCompleted = true;
  }

  static Future<bool> refreshStatus({bool silent = false}) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      _status = LicenseStatus.active;
      _trialIntroductionCompleted = true;
      _lastError = null;
      return true;
    }
    if (!isActivationConfigured) {
      _lastError = 'Ticari lisans sunucusu yapılandırılmamış.';
      return false;
    }
    if (!_secureDeviceIdentity || _devicePublicKey == null) {
      _lastError = 'Bu cihaz güvenli cihaz anahtarı oluşturamadı.';
      return false;
    }
    if (enforceServerLicense && !_officialAppSignature) {
      _lastError = 'Uygulama imzası TIVUQIPTV üretim imzasıyla eşleşmiyor.';
      return false;
    }

    try {
      final challengeResponse = await http
          .post(
            _endpoint('/v1/device/challenges'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'deviceCode': deviceId,
              'publicKey': _devicePublicKey,
              'platform': 'android_tv',
              'model': _deviceModel,
              'deviceBinding': _deviceBinding,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (challengeResponse.statusCode != 201) {
        _lastError = _serverError(challengeResponse, 'Cihaz kaydı başarısız');
        return false;
      }
      final challenge = jsonDecode(challengeResponse.body);
      if (challenge is! Map<String, dynamic>) return false;
      final challengeId = challenge['challengeId']?.toString();
      final nonce = challenge['nonce']?.toString();
      if (challengeId == null || nonce == null) {
        _lastError = 'Lisans sunucusunun doğrulama yanıtı geçersiz.';
        return false;
      }

      final signature = await _identityChannel.invokeMethod<String>(
        'signChallenge',
        {'nonce': nonce},
      );
      if (signature == null) return false;

      final verifyResponse = await http
          .post(
            _endpoint('/v1/license/verify'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'challengeId': challengeId,
              'deviceCode': deviceId,
              'signature': signature,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (verifyResponse.statusCode != 200) {
        _lastError = _serverError(
          verifyResponse,
          'Lisans doğrulaması başarısız',
        );
        return false;
      }
      final payload = jsonDecode(verifyResponse.body);
      if (payload is! Map<String, dynamic> || payload['active'] != true) {
        _status = LicenseStatus.expired;
        _lastError = 'Bu cihaz için aktif lisans bulunamadı.';
        return false;
      }
      final token = payload['licenseToken']?.toString();
      final verifiedStatus =
          token == null ? null : await _validateLicenseToken(token);
      if (verifiedStatus == null) {
        _status = LicenseStatus.expired;
        _lastError = 'Sunucunun lisans imzası doğrulanamadı.';
        return false;
      }

      final serverTrialExpiry = DateTime.tryParse(
        payload['trialExpiresAt']?.toString() ?? '',
      )?.toUtc();
      if (verifiedStatus == LicenseStatus.trial && serverTrialExpiry != null) {
        _serverTrialExpiresAt = serverTrialExpiry;
        _trialStart = serverTrialExpiry.subtract(
          const Duration(days: trialDays),
        );
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await Future.wait([
        _storage.write(key: _licenseStatusKey, value: 'active'),
        _storage.write(key: _licenseTokenKey, value: token),
        _storage.write(key: _lastVerifiedKey, value: now),
      ]);
      _status = verifiedStatus;
      _lastError = null;
      return true;
    } catch (error) {
      if (!silent) {
        _lastError = 'Lisans doğrulaması başarısız (${error.runtimeType}).';
      }
      return false;
    }
  }

  static Future<void> _loadDeviceIdentity() async {
    try {
      final result = await _identityChannel.invokeMapMethod<String, dynamic>(
        'getIdentity',
      );
      final code = result?['deviceCode']?.toString();
      final publicKey = result?['publicKey']?.toString();
      if (code != null && publicKey != null) {
        _deviceId = code;
        _devicePublicKey = publicKey;
        _deviceModel = result?['model']?.toString();
        _deviceBinding = result?['deviceBinding']?.toString();
        final actualCertificate = result?['signingCertificateSha256']
            ?.toString()
            .replaceAll(':', '')
            .toUpperCase();
        final allowedCertificates = <String>{
          _developerSigningCertificateSha256,
          ..._storeSigningCertificates
              .split(',')
              .map((value) => value.replaceAll(':', '').trim().toUpperCase())
              .where((value) => value.isNotEmpty),
        };
        _officialAppSignature = allowedCertificates.contains(actualCertificate);
        _secureDeviceIdentity = _deviceBinding != null &&
            RegExp(r'^[0-9a-f]{64}$').hasMatch(_deviceBinding!);
        return;
      }
    } on MissingPluginException {
      // Android dışı geliştirme ortamında eski kimlik yalnızca deneme için kalır.
    }

    _deviceId = await _storage.read(key: _legacyDeviceIdKey);
    if (_deviceId == null) {
      _deviceId = _generateLegacyDeviceId();
      await _storage.write(key: _legacyDeviceIdKey, value: _deviceId);
    }
    _secureDeviceIdentity = false;
  }

  static Future<LicenseStatus?> _validateLicenseToken(String token) async {
    if (!_secureDeviceIdentity || licenseServerPublicKey.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final signatureValid = await _identityChannel.invokeMethod<bool>(
      'verifyServerToken',
      {'token': token, 'publicKey': licenseServerPublicKey},
    );
    if (signatureValid != true) return null;

    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map<String, dynamic>) return null;
      final expiresAt = (payload['exp'] as num?)?.toInt();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (payload['v'] != 1 ||
          payload['deviceCode'] != deviceId ||
          expiresAt == null ||
          expiresAt <= now) {
        return null;
      }
      if (payload['status'] == 'active' && payload['kind'] == 'lifetime') {
        return LicenseStatus.active;
      }
      if (payload['status'] == 'trial' && payload['kind'] == 'trial') {
        final trialExpiresAt = (payload['trialExp'] as num?)?.toInt();
        if (trialExpiresAt == null || trialExpiresAt <= now) return null;
        _serverTrialExpiresAt = DateTime.fromMillisecondsSinceEpoch(
          trialExpiresAt * 1000,
          isUtc: true,
        );
        _trialStart = _serverTrialExpiresAt!.subtract(
          const Duration(days: trialDays),
        );
        return LicenseStatus.trial;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Uri _endpoint(String path) {
    final base = Uri.parse(licenseApiBaseUrl);
    return base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path',
    );
  }

  static String _serverError(http.Response response, String fallback) {
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic> && payload['error'] != null) {
        return '$fallback: ${payload['error']}';
      }
    } catch (_) {}
    return '$fallback (${response.statusCode}).';
  }

  static String _generateLegacyDeviceId() {
    const uuid = Uuid();
    final raw = uuid.v4().replaceAll('-', '').toUpperCase().substring(0, 12);
    return '${raw.substring(0, 4)}-${raw.substring(4, 8)}-${raw.substring(8, 12)}';
  }

  static Future<void> resetTrial() async {
    await _storage.delete(key: _trialStartKey);
    await _storage.delete(key: _licenseStatusKey);
    await _storage.delete(key: _licenseTokenKey);
    await _storage.delete(key: _lastVerifiedKey);
    await _storage.delete(key: _trialIntroductionKey);
    _trialIntroductionCompleted = false;
    await init();
  }
}
