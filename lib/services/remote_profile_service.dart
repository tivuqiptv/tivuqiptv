import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/profile.dart';
import 'license_service.dart';

class RemoteProfilePairing {
  const RemoteProfilePairing({
    required this.id,
    required this.code,
    required this.pullToken,
    required this.deviceCode,
    required this.expiresAt,
    this.setupUrl,
  });

  final String id;
  final String code;
  final String pullToken;
  final String deviceCode;
  final DateTime expiresAt;
  final Uri? setupUrl;
}

class RemoteProfileService {
  static const _identityChannel = MethodChannel(
    'com.tivuq.iptv/device_identity',
  );

  static bool get isConfigured => LicenseService.licenseApiBaseUrl.isNotEmpty;

  static Future<RemoteProfilePairing> createPairing() async {
    if (!isConfigured) throw StateError('remote_setup_not_configured');
    final identity = await _identityChannel.invokeMapMethod<String, dynamic>(
      'getIdentity',
    );
    final deviceCode = identity?['deviceCode']?.toString();
    final publicKey = identity?['publicKey']?.toString();
    final deviceBinding = identity?['deviceBinding']?.toString();
    if (deviceCode == null || publicKey == null || deviceBinding == null) {
      throw StateError('device_identity_unavailable');
    }
    final response = await http
        .post(
          _endpoint('/v1/device/profile-pairings'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'deviceCode': deviceCode,
            'publicKey': publicKey,
            'deviceBinding': deviceBinding,
            'model': identity?['model']?.toString(),
          }),
        )
        .timeout(const Duration(seconds: 10));
    final payload = jsonDecode(response.body);
    if (response.statusCode != 201 || payload is! Map<String, dynamic>) {
      throw StateError(
          payload is Map ? '${payload['error']}' : 'pairing_failed');
    }
    return RemoteProfilePairing(
      id: payload['pairingId'].toString(),
      code: payload['pairingCode'].toString(),
      pullToken: payload['pullToken'].toString(),
      deviceCode: deviceCode,
      expiresAt: DateTime.now().toUtc().add(
            Duration(seconds: (payload['expiresIn'] as num?)?.toInt() ?? 600),
          ),
      setupUrl: Uri.tryParse(payload['setupUrl']?.toString() ?? ''),
    );
  }

  static Future<Profile?> pullProfile(RemoteProfilePairing pairing) async {
    final response = await http.get(
      _endpoint('/v1/device/profile-pairings/${pairing.id}'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${pairing.pullToken}',
      },
    ).timeout(const Duration(seconds: 10));
    final payload = jsonDecode(response.body);
    if (response.statusCode != 200 || payload is! Map<String, dynamic>) {
      throw StateError(
          payload is Map ? '${payload['error']}' : 'pairing_poll_failed');
    }
    if (payload['status'] == 'expired') throw StateError('pairing_expired');
    final remote = payload['profile'];
    if (payload['status'] != 'ready' || remote is! Map) return null;
    final name = remote['name']?.toString().trim() ?? '';
    final url = remote['playlistUrl']?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    if (name.isEmpty ||
        uri == null ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme)) {
      throw StateError('invalid_remote_profile');
    }
    final initial = String.fromCharCodes(name.runes.take(2)).toUpperCase();
    return Profile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      initial: initial,
      m3uUrl: url,
    );
  }

  static Uri _endpoint(String path) {
    final base = Uri.parse(LicenseService.licenseApiBaseUrl);
    return base.replace(
        path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path');
  }
}
