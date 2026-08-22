import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/profile.dart';
import '../services/remote_profile_service.dart';
import '../theme/app_colors.dart';

class RemoteProfilePairingScreen extends StatefulWidget {
  const RemoteProfilePairingScreen({super.key});

  @override
  State<RemoteProfilePairingScreen> createState() =>
      _RemoteProfilePairingScreenState();
}

class _RemoteProfilePairingScreenState
    extends State<RemoteProfilePairingScreen> {
  RemoteProfilePairing? _pairing;
  String? _error;
  Timer? _pollTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _startPairing();
  }

  Future<void> _startPairing() async {
    _pollTimer?.cancel();
    setState(() {
      _pairing = null;
      _error = null;
    });
    try {
      final pairing = await RemoteProfileService.createPairing();
      if (!mounted) return;
      setState(() => _pairing = pairing);
      _pollTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _poll(),
      );
      await _poll();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    }
  }

  Future<void> _poll() async {
    final pairing = _pairing;
    if (_polling || pairing == null || !mounted) return;
    if (DateTime.now().toUtc().isAfter(pairing.expiresAt)) {
      _pollTimer?.cancel();
      setState(() => _error = 'Eşleştirme kodunun süresi doldu.');
      return;
    }
    _polling = true;
    try {
      final profile = await RemoteProfileService.pullProfile(pairing);
      if (profile != null && mounted) {
        _pollTimer?.cancel();
        Navigator.pop<Profile>(context, profile);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      _polling = false;
    }
  }

  String _messageFor(Object error) {
    final value = error.toString();
    if (value.contains('remote_setup_not_configured')) {
      return 'Web kurulumu henüz sunucuya bağlanmamış.';
    }
    if (value.contains('pairing_expired')) {
      return 'Eşleştirme kodunun süresi doldu.';
    }
    return 'Eşleştirme başlatılamadı. İnternet bağlantısını kontrol edin.';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _pairing;
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 36),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WEB’DEN LİSTE EKLE',
                        style: GoogleFonts.inter(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.6,
                        )),
                    const SizedBox(height: 14),
                    Text('Kumandayla uzun adres\nyazmaya gerek yok',
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 38,
                            height: 1.08,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 18),
                    Text(
                      'Telefon veya bilgisayardan sağdaki adresi açın. Cihaz kodunu, '
                      '8 haneli geçici kodu ve kişisel liste adresinizi girin. Profil '
                      'birkaç saniye içinde bu TV’ye eklenecek.',
                      style: GoogleFonts.inter(
                          color: Colors.white60, fontSize: 15, height: 1.55),
                    ),
                    const SizedBox(height: 30),
                    if (pairing == null && _error == null)
                      const CircularProgressIndicator()
                    else if (pairing != null) ...[
                      _CodeLine(label: 'CİHAZ KODU', value: pairing.deviceCode),
                      const SizedBox(height: 18),
                      _CodeLine(
                          label: 'GEÇİCİ KOD',
                          value: pairing.code,
                          large: true),
                      const SizedBox(height: 14),
                      Text(
                          'Kod 10 dakika geçerlidir ve yalnızca bir kez kullanılabilir.',
                          style: GoogleFonts.inter(
                              color: Colors.white38, fontSize: 12)),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 20),
                      Text(_error!,
                          style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: _startPairing,
                          child: const Text('Tekrar Dene')),
                    ],
                    const SizedBox(height: 30),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Geri Dön'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 64),
              Expanded(
                flex: 3,
                child: _SetupAddressCard(pairing: pairing),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeLine extends StatelessWidget {
  const _CodeLine(
      {required this.label, required this.value, this.large = false});
  final String label;
  final String value;
  final bool large;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4)),
          const SizedBox(height: 6),
          SelectableText(value,
              style: GoogleFonts.firaCode(
                  color: const Color(0xFF9A93FF),
                  fontSize: large ? 34 : 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.4)),
        ],
      );
}

class _SetupAddressCard extends StatelessWidget {
  const _SetupAddressCard({required this.pairing});
  final RemoteProfilePairing? pairing;
  @override
  Widget build(BuildContext context) {
    final url = pairing?.setupUrl;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: const Color(0xFF151123),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white10)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (url != null)
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(
                  data: url.toString(),
                  size: 180,
                  backgroundColor: Colors.white))
        else
          const SizedBox(
              width: 204,
              height: 204,
              child: Icon(Icons.qr_code_2, size: 100, color: Colors.white24)),
        const SizedBox(height: 18),
        Text(url?.toString() ?? 'Kurulum adresi hazırlanıyor…',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text('Liste adresiniz TV aldıktan sonra sunucudan silinir.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                color: Colors.white38, height: 1.4, fontSize: 11)),
      ]),
    );
  }
}
