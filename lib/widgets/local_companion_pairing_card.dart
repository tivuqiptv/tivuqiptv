import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/profile.dart';
import '../providers/settings_provider.dart';
import '../services/local_companion_service.dart';

class LocalCompanionPairingCard extends StatefulWidget {
  const LocalCompanionPairingCard({
    super.key,
    required this.onProfileReceived,
  });

  final ValueChanged<Profile> onProfileReceived;

  @override
  State<LocalCompanionPairingCard> createState() =>
      _LocalCompanionPairingCardState();
}

class _LocalCompanionPairingCardState extends State<LocalCompanionPairingCard> {
  final _settings = SettingsProvider();
  String? _code;
  Uri? _pairingUri;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    LocalCompanionService.receivedProfile.addListener(_handleProfile);
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginPairing());
  }

  void _handleProfile() {
    final profile = LocalCompanionService.receivedProfile.value;
    if (profile == null || !mounted) return;
    LocalCompanionService.receivedProfile.value = null;
    widget.onProfileReceived(profile);
  }

  String _text(String tr, String en, String de) {
    switch (_settings.language) {
      case 'tr':
        return tr;
      case 'de':
        return de;
      default:
        return en;
    }
  }

  Future<void> _beginPairing() async {
    try {
      final value = await LocalCompanionService.channel
          .invokeMapMethod<String, dynamic>('beginPairing');
      if (!mounted || value == null) return;
      final code = value['code']?.toString() ?? '';
      final address = value['address']?.toString() ?? '';
      final port = value['port']?.toString() ?? '';
      final fingerprint = value['certificateSha256']?.toString() ?? '';
      final deviceId = value['deviceId']?.toString() ?? '';
      setState(() {
        _code = code;
        _unavailable = false;
        _pairingUri = code.isEmpty ||
                address.isEmpty ||
                port == '0' ||
                fingerprint.isEmpty ||
                deviceId.isEmpty
            ? null
            : Uri(
                scheme: 'tivuq',
                host: 'pair',
                queryParameters: {
                  'deviceId': deviceId,
                  'name': value['name']?.toString() ?? 'TIVUQIPTV',
                  'address': address,
                  'port': port,
                  'fingerprint': fingerprint,
                  'code': code,
                },
              );
      });
    } on MissingPluginException {
      if (mounted) setState(() => _unavailable = true);
    } on PlatformException {
      if (mounted) setState(() => _unavailable = true);
    }
  }

  @override
  void dispose() {
    LocalCompanionService.receivedProfile.removeListener(_handleProfile);
    LocalCompanionService.channel.invokeMethod<void>('cancelPairing');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF151123),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pairingUri != null)
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                data: _pairingUri.toString(),
                size: 150,
                padding: EdgeInsets.zero,
              ),
            )
          else if (!_unavailable)
            const SizedBox(
              width: 168,
              height: 168,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            const Icon(Icons.phone_disabled_rounded,
                color: Colors.white30, size: 90),
          const SizedBox(height: 14),
          Text(
            _text(
                'TELEFONDAN EKLE', 'ADD FROM PHONE', 'VOM TELEFON HINZUFÜGEN'),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _unavailable
                ? _text('Yalnızca Android TV / Fire TV',
                    'Android TV / Fire TV only', 'Nur Android TV / Fire TV')
                : _text(
                    'TIVUQIPTV Remote ile QR kodu okutun veya $_code kodunu girin.',
                    'Scan the QR code with TIVUQIPTV Remote or enter code $_code.',
                    'Scannen Sie den QR-Code mit TIVUQIPTV Remote oder geben Sie $_code ein.',
                  ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (!_unavailable) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _beginPairing,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label:
                  Text(_text('KODU YENİLE', 'REFRESH CODE', 'CODE ERNEUERN')),
            ),
          ],
        ],
      ),
    );
  }
}
