import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_strings.dart';
import '../models/profile.dart';
import '../services/license_service.dart';
import '../services/remote_profile_service.dart';

class RemoteProfilePairingCard extends StatefulWidget {
  const RemoteProfilePairingCard({
    super.key,
    required this.onProfileReceived,
  });

  final ValueChanged<Profile> onProfileReceived;

  @override
  State<RemoteProfilePairingCard> createState() =>
      _RemoteProfilePairingCardState();
}

class _RemoteProfilePairingCardState extends State<RemoteProfilePairingCard> {
  RemoteProfilePairing? _pairing;
  Timer? _pollTimer;
  String? _error;
  bool _polling = false;
  bool _received = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    _pollTimer?.cancel();
    if (LicenseService.isDesktopVisualPreview) {
      setState(() {
        _error = null;
        _received = false;
        _pairing = RemoteProfilePairing(
          id: 'preview',
          code: '48271635',
          pullToken: 'preview',
          deviceCode: LicenseService.deviceId,
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
          setupUrl: Uri.parse('https://setup.tivuq.example/setup'),
        );
      });
      return;
    }
    setState(() {
      _pairing = null;
      _error = null;
      _received = false;
    });
    try {
      final pairing = await RemoteProfileService.createPairing();
      if (!mounted) return;
      setState(() => _pairing = pairing);
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
      await _poll();
    } catch (_) {
      if (mounted) setState(() => _error = 'unavailable');
    }
  }

  Future<void> _poll() async {
    final pairing = _pairing;
    if (_polling || pairing == null || !mounted) return;
    if (DateTime.now().toUtc().isAfter(pairing.expiresAt)) {
      _pollTimer?.cancel();
      setState(() => _error = 'expired');
      return;
    }
    _polling = true;
    try {
      final profile = await RemoteProfileService.pullProfile(pairing);
      if (profile != null && mounted) {
        _pollTimer?.cancel();
        setState(() => _received = true);
        widget.onProfileReceived(profile);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'unavailable');
    } finally {
      _polling = false;
    }
  }

  Uri? get _setupUri {
    final base = _pairing?.setupUrl;
    if (base == null || _pairing == null) return null;
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        'deviceCode': _pairing!.deviceCode,
        'pairingCode': _pairing!.code,
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final setupUri = _setupUri;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF151123),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_received)
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF59E2B0),
              size: 108,
            )
          else if (setupUri != null && _error == null)
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: setupUri.toString(),
                size: 170,
                backgroundColor: Colors.white,
              ),
            )
          else if (_error == null)
            const SizedBox(
              width: 192,
              height: 192,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            const Icon(
              Icons.wifi_off_rounded,
              color: Colors.white30,
              size: 92,
            ),
          const SizedBox(height: 17),
          Text(
            _received ? strings.playlistAdded : strings.addChannelsWithPhone,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            _received
                ? strings.playlistTransferredSecurely
                : _error == 'expired'
                    ? strings.pairingCodeExpired
                    : _error != null
                        ? strings.pairingUnavailable
                        : setupUri == null
                            ? strings.pairingCodePreparing
                            : strings.scanChannelSetupQr,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 13),
            OutlinedButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(strings.retry),
            ),
          ] else if (!_received && _pairing != null) ...[
            const SizedBox(height: 11),
            Text(
              strings.oneTimeSecureCode,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white30,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
