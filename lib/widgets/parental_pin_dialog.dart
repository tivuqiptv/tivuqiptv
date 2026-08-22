import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/settings_provider.dart';
import '../utils/instant_dialog.dart';

Future<bool> requestParentalPin(
  BuildContext context, {
  required SettingsProvider settings,
  String? profileId,
  bool createPin = false,
  bool waitForSelectRelease = false,
}) async {
  final result = await showInstantDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ParentalPinDialog(
      settings: settings,
      profileId: profileId,
      createPin: createPin,
      waitForSelectRelease: waitForSelectRelease,
    ),
  );
  return result ?? false;
}

class _ParentalPinDialog extends StatefulWidget {
  const _ParentalPinDialog({
    required this.settings,
    required this.profileId,
    required this.createPin,
    required this.waitForSelectRelease,
  });

  final SettingsProvider settings;
  final String? profileId;
  final bool createPin;
  final bool waitForSelectRelease;

  @override
  State<_ParentalPinDialog> createState() => _ParentalPinDialogState();
}

class _ParentalPinDialogState extends State<_ParentalPinDialog> {
  final FocusNode _focusNode = FocusNode();
  String _pin = '';
  String? _firstPin;
  String? _error;
  int _focusedIndex = 0;
  late bool _acceptInput;

  bool get _isConfirming => widget.createPin && _firstPin != null;

  @override
  void initState() {
    super.initState();
    _acceptInput = !widget.waitForSelectRelease;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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

  void _append(String digit) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _delete() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_pin.length < 4) {
      setState(() => _error = _text(
            'PIN en az 4 rakam olmalı',
            'PIN must contain at least 4 digits',
            'Die PIN muss mindestens 4 Ziffern haben',
          ));
      return;
    }
    if (!widget.createPin) {
      if (widget.settings.verifyParentalPin(
        _pin,
        profileId: widget.profileId,
      )) {
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() {
          _pin = '';
          _error = _text('PIN yanlış', 'Incorrect PIN', 'Falsche PIN');
        });
      }
      return;
    }
    if (_firstPin == null) {
      setState(() {
        _firstPin = _pin;
        _pin = '';
      });
      return;
    }
    if (_pin != _firstPin) {
      setState(() {
        _firstPin = null;
        _pin = '';
        _error = _text(
          'PIN kodları eşleşmedi',
          'PIN codes did not match',
          'Die PIN-Codes stimmen nicht überein',
        );
      });
      return;
    }
    final saved = await widget.settings.setParentalPin(
      _pin,
      profileId: widget.profileId,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = _text(
            'PIN kaydedilemedi',
            'PIN could not be saved',
            'Die PIN konnte nicht gespeichert werden',
          ));
    }
  }

  void _activate() {
    if (_focusedIndex <= 8) {
      _append('${_focusedIndex + 1}');
    } else if (_focusedIndex == 9) {
      _delete();
    } else if (_focusedIndex == 10) {
      _append('0');
    } else {
      _submit();
    }
  }

  KeyEventResult _handleKey(KeyEvent event) {
    final key = event.logicalKey;
    final isSelect =
        key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;
    if (!_acceptInput) {
      if (event is KeyUpEvent && isSelect) {
        _acceptInput = true;
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      if (_pin.isNotEmpty) {
        _delete();
      } else {
        Navigator.pop(context, false);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _focusedIndex = (_focusedIndex - 1).clamp(0, 11));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _focusedIndex = (_focusedIndex + 1).clamp(0, 11));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _focusedIndex = (_focusedIndex - 3).clamp(0, 11));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _focusedIndex = (_focusedIndex + 3).clamp(0, 11));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _activate();
      return KeyEventResult.handled;
    }
    final digit = int.tryParse(event.character ?? '');
    if (digit != null) {
      _append('$digit');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final labels = <Widget>[
      for (var i = 1; i <= 9; i++) Text('$i'),
      const Icon(Icons.backspace_outlined),
      const Text('0'),
      const Icon(Icons.check_rounded),
    ];
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) => _handleKey(event),
      child: Dialog(
        backgroundColor: const Color(0xFF171329),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 340,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    color: settings.primaryColor, size: 30),
                const SizedBox(height: 10),
                Text(
                  widget.createPin
                      ? (_isConfirming
                          ? _text('PIN kodunu doğrulayın', 'Confirm PIN',
                              'PIN bestätigen')
                          : _text('Yeni ebeveyn PIN kodu', 'New parental PIN',
                              'Neue Eltern-PIN'))
                      : _text('Ebeveyn PIN kodu', 'Parental PIN', 'Eltern-PIN'),
                  style: GoogleFonts.notoSans(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  List.filled(_pin.length, '●').join('  '),
                  style: TextStyle(
                    color: settings.primaryColor,
                    fontSize: 20,
                    letterSpacing: 3,
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: _error == null
                      ? null
                      : Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 11,
                            ),
                          ),
                        ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.7,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: labels.length,
                  itemBuilder: (_, index) {
                    final focused = index == _focusedIndex;
                    return AnimatedContainer(
                      duration: Duration.zero,
                      decoration: BoxDecoration(
                        color: focused
                            ? settings.primaryColor
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: focused ? Colors.white : Colors.white12,
                          width: focused ? 2 : 1,
                        ),
                      ),
                      child: IconTheme(
                        data:
                            const IconThemeData(color: Colors.white, size: 20),
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          child: Center(child: labels[index]),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
