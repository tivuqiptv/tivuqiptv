import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../player/player_adapter.dart';
import '../providers/settings_provider.dart';
import '../services/player_engine.dart';
import '../utils/instant_dialog.dart';

Future<void> showTrackSelectionDialog(
  BuildContext context, {
  required AppPlayerEngine playerEngine,
  required SettingsProvider settings,
}) {
  return showInstantDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TrackSelectionDialog(
      playerEngine: playerEngine,
      settings: settings,
    ),
  );
}

class _TrackChoice {
  const _TrackChoice(this.type, this.track);
  final String type;
  final PlayerTrackOption track;
}

class _TrackSelectionDialog extends StatefulWidget {
  const _TrackSelectionDialog({
    required this.playerEngine,
    required this.settings,
  });

  final AppPlayerEngine playerEngine;
  final SettingsProvider settings;

  @override
  State<_TrackSelectionDialog> createState() => _TrackSelectionDialogState();
}

class _TrackSelectionDialogState extends State<_TrackSelectionDialog> {
  final FocusNode _focusNode = FocusNode();
  List<_TrackChoice> _choices = const [];
  bool _loading = true;
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    final results = await Future.wait([
      widget.playerEngine.getAudioTracks(),
      widget.playerEngine.getSubtitleTracks(),
    ]);
    if (!mounted) return;
    final audio = results[0];
    final subtitles = results[1];
    final choices = <_TrackChoice>[
      if (audio.length > 1)
        ...audio.map((track) => _TrackChoice('audio', track)),
      if (subtitles.any((track) => !track.isOff))
        ...subtitles.map((track) => _TrackChoice('subtitle', track)),
    ];
    setState(() {
      _choices = choices;
      _loading = false;
      final selected = choices.indexWhere((choice) => choice.track.isSelected);
      _focusedIndex = selected >= 0 ? selected : 0;
    });
  }

  Future<void> _selectFocused() async {
    if (_choices.isEmpty) return;
    final choice = _choices[_focusedIndex];
    if (choice.type == 'audio') {
      await widget.playerEngine.selectAudioTrack(choice.track.id);
    } else {
      await widget.playerEngine.selectSubtitleTrack(choice.track.id);
    }
    await _load();
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (_choices.isEmpty) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() =>
          _focusedIndex = (_focusedIndex - 1).clamp(0, _choices.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() =>
          _focusedIndex = (_focusedIndex + 1).clamp(0, _choices.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _selectFocused();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) => _handleKey(event),
      child: Dialog(
        backgroundColor: const Color(0xFF171329),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 440,
          height: 430,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.subtitles_outlined,
                        color: settings.primaryColor),
                    const SizedBox(width: 10),
                    Text(
                      _text('Ses ve Altyazı', 'Audio & Subtitles',
                          'Audio & Untertitel'),
                      style: GoogleFonts.notoSans(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: settings.primaryColor,
                          ),
                        )
                      : _choices.isEmpty
                          ? Center(
                              child: Text(
                                _text(
                                  'Bu yayında alternatif ses veya altyazı yok',
                                  'No alternate audio or subtitles are available',
                                  'Keine alternativen Audio- oder Untertitelspuren verfügbar',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white60),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _choices.length,
                              itemBuilder: (_, index) {
                                final choice = _choices[index];
                                final focused = index == _focusedIndex;
                                return AnimatedContainer(
                                  duration: Duration.zero,
                                  margin: const EdgeInsets.only(bottom: 7),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: focused
                                        ? settings.primaryColor
                                            .withValues(alpha: 0.22)
                                        : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: focused
                                          ? Colors.white
                                          : Colors.transparent,
                                      width: focused ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        choice.type == 'audio'
                                            ? Icons.audiotrack_rounded
                                            : Icons.closed_caption_rounded,
                                        color: Colors.white70,
                                        size: 19,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          choice.track.isOff
                                              ? _text('Kapalı', 'Off', 'Aus')
                                              : choice.track.label,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      if (choice.track.isSelected)
                                        Icon(Icons.check_circle_rounded,
                                            color: settings.primaryColor,
                                            size: 19),
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
