import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/settings_provider.dart';
import '../services/local_companion_service.dart';

class LocalCompanionDialog extends StatefulWidget {
  const LocalCompanionDialog({super.key, required this.settings});

  final SettingsProvider settings;

  @override
  State<LocalCompanionDialog> createState() => _LocalCompanionDialogState();
}

class _LocalCompanionDialogState extends State<LocalCompanionDialog> {
  final FocusNode _focusNode = FocusNode();
  Timer? _refreshTimer;
  String? _code;
  int? _expiresAt;
  List<Map<String, dynamic>> _devices = const [];
  int _focusedIndex = 0;
  bool _available = true;
  Uri? _pairingUri;

  @override
  void initState() {
    super.initState();
    _beginPairing();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _loadDevices(),
    );
  }

  String _text(String tr, String en, String de) {
    switch (widget.settings.language) {
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
      setState(() {
        _available = true;
        _code = value['code']?.toString();
        _expiresAt = value['expiresAt'] as int?;
        final address = value['address']?.toString() ?? '';
        final port = value['port']?.toString() ?? '';
        final fingerprint = value['certificateSha256']?.toString() ?? '';
        final deviceId = value['deviceId']?.toString() ?? '';
        _pairingUri = address.isEmpty ||
                port == '0' ||
                fingerprint.isEmpty ||
                deviceId.isEmpty ||
                _code == null
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
                  'code': _code!,
                },
              );
      });
      await _loadDevices();
    } on MissingPluginException {
      if (mounted) setState(() => _available = false);
    } on PlatformException {
      if (mounted) setState(() => _available = false);
    }
  }

  Future<void> _loadDevices() async {
    try {
      final values = await LocalCompanionService.channel
              .invokeListMethod<dynamic>('getPairedDevices') ??
          const [];
      if (!mounted) return;
      setState(() {
        _devices = values
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList(growable: false);
        _focusedIndex = _focusedIndex.clamp(0, _devices.length);
      });
    } catch (_) {
      // A transient refresh failure must not close the pairing screen.
    }
  }

  Future<void> _activate() async {
    if (_focusedIndex == 0) {
      await _beginPairing();
      return;
    }
    final index = _focusedIndex - 1;
    if (index < 0 || index >= _devices.length) return;
    await LocalCompanionService.channel.invokeMethod<void>(
      'revokeDevice',
      {'id': _devices[index]['id']},
    );
    await _loadDevices();
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
          () => _focusedIndex = (_focusedIndex - 1).clamp(0, _devices.length));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(
          () => _focusedIndex = (_focusedIndex + 1).clamp(0, _devices.length));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _focusNode.dispose();
    LocalCompanionService.channel.invokeMethod<void>('cancelPairing');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remainingSeconds = _expiresAt == null
        ? 0
        : ((_expiresAt! - DateTime.now().millisecondsSinceEpoch) / 1000)
            .ceil()
            .clamp(0, 300);
    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (_, event) => _handleKey(event),
      child: Dialog(
        backgroundColor: const Color(0xFF171329),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 570,
          height: 480,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text('TELEFON BAĞLANTISI', 'PHONE CONNECTION',
                      'TELEFONVERBINDUNG'),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _text(
                    'TIVUQIPTV Remote uygulamasını aynı Wi‑Fi ağına bağlayın ve aşağıdaki kodu telefona girin.',
                    'Connect TIVUQIPTV Remote to the same Wi-Fi and enter this code on the phone.',
                    'Verbinden Sie TIVUQIPTV Remote mit demselben WLAN und geben Sie diesen Code ein.',
                  ),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 18),
                AnimatedContainer(
                  duration: Duration.zero,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: widget.settings.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _focusedIndex == 0
                          ? widget.settings.primaryColor
                          : Colors.white12,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            !_available
                                ? _text(
                                    'Bu cihazda kullanılamıyor',
                                    'Unavailable on this device',
                                    'Auf diesem Gerät nicht verfügbar')
                                : (_code ?? '------'),
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: _available ? 40 : 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: _available ? 12 : 0,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _available
                                ? _text(
                                    '$remainingSeconds saniye geçerli · Yenilemek için OK',
                                    'Valid for $remainingSeconds seconds · Press OK to refresh',
                                    '$remainingSeconds Sekunden gültig · OK zum Erneuern',
                                  )
                                : _text(
                                    'Yalnızca Android TV / Fire TV',
                                    'Android TV / Fire TV only',
                                    'Nur Android TV / Fire TV'),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                      if (_pairingUri != null) ...[
                        const SizedBox(width: 24),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: QrImageView(
                            data: _pairingUri.toString(),
                            size: 92,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _text('EŞLEŞMİŞ TELEFONLAR', 'PAIRED PHONES',
                      'GEKOPPELTE TELEFONE'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Expanded(
                  child: _devices.isEmpty
                      ? Center(
                          child: Text(
                            _text(
                                'Henüz eşleşmiş telefon yok',
                                'No paired phone yet',
                                'Noch kein Telefon gekoppelt'),
                            style: const TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _devices.length,
                          itemExtent: 54,
                          itemBuilder: (context, index) {
                            final focused = _focusedIndex == index + 1;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF292348),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: focused
                                      ? widget.settings.primaryColor
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.phone_android_rounded,
                                      color: Colors.white70, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _devices[index]['name']?.toString() ??
                                          'TIVUQIPTV Remote',
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  Text(
                                    _text('OK: KALDIR', 'OK: REMOVE',
                                        'OK: ENTFERNEN'),
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
