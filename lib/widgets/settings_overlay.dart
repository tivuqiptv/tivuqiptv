import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/settings_provider.dart';
import '../models/profile.dart';
import 'parental_pin_dialog.dart';
import 'track_selection_dialog.dart';
import '../services/player_engine.dart';
import '../services/license_service.dart';
import 'local_companion_dialog.dart';
import '../utils/instant_dialog.dart';

class SettingsOverlay extends StatefulWidget {
  final VoidCallback? onClose;
  final Profile? profile;
  final bool vodPlaybackSettings;
  final AppPlayerEngine? playerEngine;
  final bool? selectableTracksAvailable;

  const SettingsOverlay({
    super.key,
    this.onClose,
    this.profile,
    this.vodPlaybackSettings = false,
    this.playerEngine,
    this.selectableTracksAvailable,
  });

  @override
  State<SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay> {
  int _focusedRowIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<GlobalKey> _keys = List.generate(13, (index) => GlobalKey());
  bool _childDialogOpen = false;
  DateTime? _childDialogClosedAt;

  static const _childBackPropagationGuard = Duration(milliseconds: 600);

  bool get _hasTrackSelector => widget.playerEngine != null;
  int get _profileRowIndex => _hasTrackSelector ? 12 : 11;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToFocused() {
    if (_focusedRowIndex >= 0 && _focusedRowIndex < _keys.length) {
      final context = _keys[_focusedRowIndex].currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: Duration.zero,
        );
      }
    }
  }

  void _handleLeftRight(int delta) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    switch (_focusedRowIndex) {
      case 0:
        final opts = widget.vodPlaybackSettings
            ? ['legacy', 'fireTvMedia3', 'vlc']
            : ['legacy', 'fireTvMedia3'];
        final selectedEngine = widget.vodPlaybackSettings
            ? settings.vodPreferredEngine
            : settings.preferredEngine;
        int idx = opts.indexOf(selectedEngine);
        if (idx == -1) idx = 0;
        int nextIdx = (idx + delta).clamp(0, opts.length - 1);
        if (widget.vodPlaybackSettings) {
          settings.updateSettings(vodPreferredEngine: opts[nextIdx]);
        } else {
          settings.updateSettings(preferredEngine: opts[nextIdx]);
        }
        break;
      case 1:
        final opts = ['auto', '4k', '1080p', '720p'];
        int idx = opts.indexOf(settings.quality);
        if (idx == -1) idx = 0;
        int nextIdx = (idx + delta).clamp(0, opts.length - 1);
        settings.updateSettings(quality: opts[nextIdx]);
        break;
      case 2:
        settings.updateSettings(
          liveTvRefreshRate: delta > 0 ? 60 : 50,
        );
        break;
      case 3:
        final opts = ['tr', 'en', 'de'];
        int idx = opts.indexOf(settings.language);
        if (idx == -1) idx = 0;
        int nextIdx = (idx + delta).clamp(0, opts.length - 1);
        settings.updateSettings(language: opts[nextIdx]);
        break;
      case 4:
        double newOp = (settings.sidebarOpacity + (delta * 0.01)).clamp(
          0.0,
          1.0,
        );
        newOp = double.parse(newOp.toStringAsFixed(2));
        settings.updateSettings(sidebarOpacity: newOp);
        break;
      case 5:
        final opts = [
          0.0,
          0.25,
          0.5,
          0.75,
          1.0,
          1.25,
          1.5,
          1.75,
          2.0,
          2.5,
          3.0,
          3.5,
          4.0,
          4.5,
          5.0,
          5.5,
          6.0,
          6.5,
          7.0,
          7.5,
          8.0,
          8.5,
          9.0,
          9.5,
          10.0,
          10.5,
          11.0,
          11.5,
          12.0,
          12.5,
          13.0,
          13.5,
          14.0,
          14.5,
          15.0,
        ];
        int idx = opts.indexOf(settings.autoHideDuration);
        if (idx == -1) {
          double closest = 3.0;
          double minDiff = 999.0;
          for (var opt in opts) {
            double diff = (opt - settings.autoHideDuration).abs();
            if (diff < minDiff) {
              minDiff = diff;
              closest = opt;
            }
          }
          idx = opts.indexOf(closest);
        }
        int nextIdx = (idx + delta).clamp(0, opts.length - 1);
        settings.updateSettings(autoHideDuration: opts[nextIdx]);
        break;
      case 6:
        final opts = [
          const Color(0xFF6366F1),
          const Color(0xFFEC4899),
          const Color(0xFFF59E0B),
          const Color(0xFF10B981),
          const Color(0xFF3B82F6),
          const Color(0xFFEF4444),
          const Color(0xFF8B5CF6),
        ];
        int idx = opts.indexOf(settings.primaryColor);
        if (idx == -1) idx = 0;
        int nextIdx = (idx + delta).clamp(0, opts.length - 1);
        settings.updateSettings(primaryColor: opts[nextIdx]);
        break;
      case 7:
        final opts = ['live_tv', 'movies', 'series', 'last_screen'];
        int idx = opts.indexOf(settings.startupScreen);
        if (idx == -1) idx = 0;
        int nextIdx = (idx + delta).clamp(0, opts.length - 1);
        settings.updateSettings(startupScreen: opts[nextIdx]);
        break;
      case 8:
        settings.updateSettings(autoStartOnBoot: !settings.autoStartOnBoot);
        break;
    }
  }

  Future<void> _toggleParentalControl(SettingsProvider settings) async {
    final profileId = widget.profile?.id ?? settings.lastProfileId;
    final enabled = settings.hasParentalPin(profileId: profileId);
    if (!enabled) {
      final created = await _runChildDialog(
        () => requestParentalPin(
          context,
          settings: settings,
          profileId: profileId,
          createPin: true,
        ),
      );
      if (created != true || !mounted) return;
    } else {
      final verified = await _runChildDialog(
        () => requestParentalPin(
          context,
          settings: settings,
          profileId: profileId,
        ),
      );
      if (verified != true || !mounted) return;
    }
    await _runChildDialog(
      () => showInstantDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _HiddenCategoriesDialog(
          settings: settings,
          profileId: profileId,
        ),
      ),
    );
  }

  Future<T?> _runChildDialog<T>(Future<T?> Function() open) async {
    _childDialogOpen = true;
    try {
      return await open();
    } finally {
      _childDialogOpen = false;
      _childDialogClosedAt = DateTime.now();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }
    }
  }

  Future<void> _openCompanionDialog(SettingsProvider settings) async {
    await _runChildDialog(
      () => showInstantDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => LocalCompanionDialog(settings: settings),
      ),
    );
  }

  Widget _buildFocusWrapper(int index, Widget child) {
    final bool isFocused = _focusedRowIndex == index;
    return Container(
      key: _keys[index],
      child: AnimatedContainer(
        duration: Duration.zero,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFocused ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final key = event.logicalKey;

            if (_childDialogOpen) return KeyEventResult.handled;

            if (key == LogicalKeyboardKey.escape ||
                key == LogicalKeyboardKey.goBack) {
              final childDialogClosedAt = _childDialogClosedAt;
              if (childDialogClosedAt != null &&
                  DateTime.now().difference(childDialogClosedAt) <
                      _childBackPropagationGuard) {
                // Fire TV can deliver the same Back press to this parent after
                // the child route has already completed. Consume only that
                // trailing event so the settings overlay remains open.
                return KeyEventResult.handled;
              }
              if (widget.onClose != null) {
                widget.onClose!();
              } else {
                Navigator.pop(context);
              }
              return KeyEventResult.handled;
            }

            if (key == LogicalKeyboardKey.arrowDown) {
              setState(() {
                _focusedRowIndex =
                    (_focusedRowIndex + 1).clamp(0, _profileRowIndex);
              });
              _scrollToFocused();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowUp) {
              setState(() {
                _focusedRowIndex =
                    (_focusedRowIndex - 1).clamp(0, _profileRowIndex);
              });
              _scrollToFocused();
              return KeyEventResult.handled;
            }

            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter) {
              if (_focusedRowIndex == 8) {
                settings.updateSettings(
                  autoStartOnBoot: !settings.autoStartOnBoot,
                );
                return KeyEventResult.handled;
              }
              if (_focusedRowIndex == 9) {
                _toggleParentalControl(settings);
                return KeyEventResult.handled;
              }
              if (_focusedRowIndex == 10) {
                _openCompanionDialog(settings);
                return KeyEventResult.handled;
              }
              if (_hasTrackSelector && _focusedRowIndex == 11) {
                showTrackSelectionDialog(
                  context,
                  playerEngine: widget.playerEngine!,
                  settings: settings,
                );
                return KeyEventResult.handled;
              }
              if (_focusedRowIndex == _profileRowIndex) {
                Navigator.pop(context, 'open_profiles');
                return KeyEventResult.handled;
              }
            }

            if (key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.arrowRight) {
              int delta = key == LogicalKeyboardKey.arrowRight ? 1 : -1;
              _handleLeftRight(delta);
              return KeyEventResult.handled;
            }

            return KeyEventResult.ignored;
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                // Optimized background without blur for better TV performance
                GestureDetector(
                  onTap: widget.onClose ?? () => Navigator.pop(context),
                  child: Container(
                    color: Colors.black.withValues(
                      alpha: 0.8 * settings.sidebarOpacity,
                    ),
                  ),
                ),

                // Settings Dialog
                Center(
                  child: Container(
                    width: 550, // Reduced width
                    height: MediaQuery.of(context).size.height * 0.85,
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFF131022,
                      ).withValues(alpha: settings.sidebarOpacity),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: 0.05 * settings.sidebarOpacity,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: 0.5 * settings.sidebarOpacity,
                          ),
                          blurRadius: 100,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              padding: const EdgeInsets.only(
                                left: 16,
                                right: 16,
                                top: 24,
                                bottom: 72,
                              ),
                              child: Column(
                                children: [
                                  _buildTitleSection(settings),
                                  const SizedBox(height: 12),
                                  _buildFocusWrapper(
                                    0,
                                    _buildPlaybackEngineSection(settings),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildFocusWrapper(
                                    1,
                                    _buildQualitySection(settings),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildFocusWrapper(
                                    2,
                                    _buildLiveRefreshRateSection(settings),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildFocusWrapper(
                                    3,
                                    _buildLanguageSection(settings),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildFocusWrapper(
                                    4,
                                    _buildOpacitySection(settings),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildFocusWrapper(
                                    5,
                                    _buildAutoHideSection(settings),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildFocusWrapper(
                                    6,
                                    _buildIconColorSection(settings),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildFocusWrapper(
                                    7,
                                    _buildStartupSection(settings),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildFocusWrapper(
                                    8,
                                    _buildAutoStartSection(settings),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildFocusWrapper(
                                    9,
                                    _buildParentalSection(settings),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildFocusWrapper(
                                    10,
                                    _buildCompanionSection(settings),
                                  ),
                                  const SizedBox(height: 4),
                                  if (_hasTrackSelector) ...[
                                    _buildFocusWrapper(
                                      11,
                                      _buildTrackSection(settings),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  _buildFocusWrapper(
                                    _profileRowIndex,
                                    _buildProfileSection(settings),
                                  ),
                                  const SizedBox(height: 14),
                                  _buildAutoSaveHint(settings),
                                  const SizedBox(height: 10),
                                  _buildDeviceCode(settings),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ), // closes Stack
          ), // closes Scaffold
        ); // closes Focus
      },
    );
  }

  // Header removed for TV full-screen usage

  Widget _buildTitleSection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tune, color: settings.primaryColor, size: 16),
            const SizedBox(width: 8),
            Text(
              settings.getTranslatedText('system_settings', settings.language),
              style: GoogleFonts.manrope(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          settings.getTranslatedText('player_prefs', settings.language),
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.person,
          settings.language == 'tr' ? 'KULLANICI PROFİLLERİ' : 'USER PROFILES',
          settings,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context, 'open_profiles'),
                child: AnimatedContainer(
                  duration: Duration.zero,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: _focusedRowIndex == _profileRowIndex
                        ? settings.primaryColor.withValues(alpha: 0.1)
                        : const Color(0xFF292348).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _focusedRowIndex == _profileRowIndex
                          ? settings.primaryColor
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.switch_account,
                        color: _focusedRowIndex == _profileRowIndex
                            ? settings.primaryColor
                            : const Color(0xFF9B92C9),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            settings.language == 'tr'
                                ? 'Kullanıcı Değiştir veya Ekle'
                                : 'Switch or Add User',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            widget.profile != null
                                ? (settings.language == 'tr'
                                    ? 'Mevcut: ${widget.profile!.name}'
                                    : 'Current: ${widget.profile!.name}')
                                : '',
                            style: const TextStyle(
                              color: Color(0xFF9B92C9),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Color(0xFF9B92C9),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildParentalSection(SettingsProvider settings) {
    final profileId = widget.profile?.id ?? settings.lastProfileId;
    final enabled = settings.hasParentalPin(profileId: profileId);
    String title;
    String description;
    switch (settings.language) {
      case 'tr':
        title = 'EBEVEYN KONTROLÜ';
        description = enabled
            ? 'Gizli kategorileri PIN ile görüntüleyin ve yönetin'
            : 'PIN oluşturun · Kategoride uzun OK ile gizleyin';
        break;
      case 'de':
        title = 'KINDERSICHERUNG';
        description = enabled
            ? 'Ausgeblendete Kategorien mit PIN anzeigen und verwalten'
            : 'PIN erstellen · Kategorie mit langem OK ausblenden';
        break;
      default:
        title = 'PARENTAL CONTROL';
        description = enabled
            ? 'Enter PIN to view and manage hidden categories'
            : 'Create a PIN · Long-press OK on a category to hide it';
        break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.shield_outlined, title, settings),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _toggleParentalControl(settings),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: _focusedRowIndex == 9
                  ? settings.primaryColor.withValues(alpha: 0.12)
                  : const Color(0xFF292348).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _focusedRowIndex == 9
                    ? settings.primaryColor
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  enabled
                      ? Icons.visibility_off_rounded
                      : Icons.shield_outlined,
                  color: enabled ? settings.primaryColor : Colors.white54,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    description,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
                Text(
                  enabled
                      ? (settings.language == 'de'
                          ? 'EIN'
                          : settings.language == 'tr'
                              ? 'AÇIK'
                              : 'ON')
                      : (settings.language == 'de'
                          ? 'AUS'
                          : settings.language == 'tr'
                              ? 'KAPALI'
                              : 'OFF'),
                  style: TextStyle(
                    color: enabled ? settings.primaryColor : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompanionSection(SettingsProvider settings) {
    final title = settings.language == 'tr'
        ? 'TELEFON BAĞLANTISI'
        : settings.language == 'de'
            ? 'TELEFONVERBINDUNG'
            : 'PHONE CONNECTION';
    final description = settings.language == 'tr'
        ? 'TIVUQIPTV Remote ile eşleştirin, kumanda edin ve liste gönderin'
        : settings.language == 'de'
            ? 'TIVUQIPTV Remote koppeln, steuern und Listen übertragen'
            : 'Pair TIVUQIPTV Remote, control the TV and send playlists';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.phone_android_rounded, title, settings),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _openCompanionDialog(settings),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: _focusedRowIndex == 10
                  ? settings.primaryColor.withValues(alpha: 0.12)
                  : const Color(0xFF292348).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _focusedRowIndex == 10
                    ? settings.primaryColor
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.phonelink_lock_rounded,
                    color: settings.primaryColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    description,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white38, size: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackSection(SettingsProvider settings) {
    final hasTracks = widget.selectableTracksAvailable != false;
    final title = settings.language == 'tr'
        ? 'SES VE ALTYAZI'
        : settings.language == 'de'
            ? 'AUDIO UND UNTERTITEL'
            : 'AUDIO & SUBTITLES';
    final description = hasTracks
        ? (settings.language == 'tr'
            ? 'İçerikteki alternatif ses ve altyazı parçalarını seçin'
            : settings.language == 'de'
                ? 'Alternative Audio- und Untertitelspuren auswählen'
                : 'Choose alternate audio and subtitle tracks')
        : (settings.language == 'tr'
            ? 'Bu içerikte alternatif ses veya altyazı bulunmuyor'
            : settings.language == 'de'
                ? 'Dieser Inhalt enthält keine alternativen Audio- oder Untertitelspuren'
                : 'This content has no alternate audio or subtitle tracks');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.subtitles_outlined, title, settings),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => showTrackSelectionDialog(
            context,
            playerEngine: widget.playerEngine!,
            settings: settings,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: _focusedRowIndex == 11
                  ? settings.primaryColor.withValues(alpha: 0.12)
                  : const Color(0xFF292348).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _focusedRowIndex == 11
                    ? settings.primaryColor
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasTracks
                      ? Icons.audiotrack_rounded
                      : Icons.info_outline_rounded,
                  color: hasTracks ? settings.primaryColor : Colors.white54,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    description,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white38, size: 13),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStartupSection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.launch_outlined,
          settings
              .getTranslatedText('startup_screen', settings.language)
              .toUpperCase(),
          settings,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildOptionTile(
              settings.getTranslatedText('live_tv', settings.language),
              Icons.live_tv,
              '',
              settings.startupScreen == 'live_tv',
              () => settings.updateSettings(startupScreen: 'live_tv'),
              settings,
            ),
            const SizedBox(width: 8),
            _buildOptionTile(
              settings.getTranslatedText('movies', settings.language),
              Icons.movie_outlined,
              '',
              settings.startupScreen == 'movies',
              () => settings.updateSettings(startupScreen: 'movies'),
              settings,
            ),
            const SizedBox(width: 8),
            _buildOptionTile(
              settings.getTranslatedText('series', settings.language),
              Icons.tv,
              '',
              settings.startupScreen == 'series',
              () => settings.updateSettings(startupScreen: 'series'),
              settings,
            ),
            const SizedBox(width: 8),
            _buildOptionTile(
              settings.getTranslatedText('last_screen', settings.language),
              Icons.history,
              '',
              settings.startupScreen == 'last_screen',
              () => settings.updateSettings(startupScreen: 'last_screen'),
              settings,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAutoStartSection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.power_settings_new,
          settings
              .getTranslatedText('auto_start_on_boot', settings.language)
              .toUpperCase(),
          settings,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildOptionTile(
              settings.getTranslatedText(
                'auto_start_on_boot',
                settings.language,
              ),
              Icons.rocket_launch_outlined,
              settings.getTranslatedText(
                'auto_start_on_boot_desc',
                settings.language,
              ),
              settings.autoStartOnBoot,
              () => settings.updateSettings(
                autoStartOnBoot: !settings.autoStartOnBoot,
              ),
              settings,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(
    IconData icon,
    String title,
    SettingsProvider settings,
  ) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.notoSans(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackEngineSection(SettingsProvider settings) {
    final selectedEngine = widget.vodPlaybackSettings
        ? settings.vodPreferredEngine
        : settings.preferredEngine;
    void selectEngine(String engine) {
      if (widget.vodPlaybackSettings) {
        settings.updateSettings(vodPreferredEngine: engine);
      } else {
        settings.updateSettings(preferredEngine: engine);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.video_settings,
          settings.language == 'tr' ? 'OYNATICI MOTORU' : 'PLAYBACK ENGINE',
          settings,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildOptionTile(
              'ExoPlayer2',
              Icons.history,
              settings.language == 'tr'
                  ? 'Uyumlu Native Surface'
                  : 'Compatible Native Surface',
              selectedEngine == 'legacy',
              () => selectEngine('legacy'),
              settings,
            ),
            const SizedBox(width: 8),
            _buildOptionTile(
              'Media3',
              Icons.bolt,
              settings.language == 'tr'
                  ? 'Yeni Android Motoru'
                  : 'Modern Android Engine',
              selectedEngine == 'fireTvMedia3',
              () => selectEngine('fireTvMedia3'),
              settings,
            ),
            if (widget.vodPlaybackSettings) ...[
              const SizedBox(width: 8),
              _buildOptionTile(
                'VLC',
                Icons.play_circle_outline,
                settings.language == 'tr'
                    ? 'Film/Dizi Uyumluluğu'
                    : 'Movie/Series Compatibility',
                selectedEngine == 'vlc',
                () => selectEngine('vlc'),
                settings,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildQualitySection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.high_quality,
          settings
              .getTranslatedText('video_quality', settings.language)
              .toUpperCase(),
          settings,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildOptionTile(
              settings.getTranslatedText('auto', settings.language),
              Icons.auto_awesome,
              settings.getTranslatedText('auto_desc', settings.language),
              settings.quality == 'auto',
              () => settings.updateSettings(quality: 'auto'),
              settings,
            ),
            const SizedBox(width: 8),
            _buildOptionTile(
              '4K',
              Icons.four_k_outlined,
              'Ultra HD',
              settings.quality == '4k',
              () => settings.updateSettings(quality: '4k'),
              settings,
            ),
            const SizedBox(width: 8),
            _buildOptionTile(
              '1080p',
              Icons.hd_outlined,
              'Full HD',
              settings.quality == '1080p',
              () => settings.updateSettings(quality: '1080p'),
              settings,
            ),
            const SizedBox(width: 8),
            _buildOptionTile(
              '720p',
              Icons.sd_outlined,
              settings.language == 'tr' ? 'Std' : 'Std',
              settings.quality == '720p',
              () => settings.updateSettings(quality: '720p'),
              settings,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLiveRefreshRateSection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.monitor_rounded,
          settings
              .getTranslatedText('live_tv_refresh_rate', settings.language)
              .toUpperCase(),
          settings,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildOptionTile(
              '50 Hz',
              Icons.tv_rounded,
              settings.getTranslatedText(
                'live_tv_refresh_50_desc',
                settings.language,
              ),
              settings.liveTvRefreshRate == 50,
              () => settings.updateSettings(liveTvRefreshRate: 50),
              settings,
            ),
            const SizedBox(width: 8),
            _buildOptionTile(
              '60 Hz',
              Icons.tv_rounded,
              settings.getTranslatedText(
                'live_tv_refresh_60_desc',
                settings.language,
              ),
              settings.liveTvRefreshRate == 60,
              () => settings.updateSettings(liveTvRefreshRate: 60),
              settings,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLanguageSection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.translate,
          settings
              .getTranslatedText('lang_selection', settings.language)
              .toUpperCase(),
          settings,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildLanguageTile('🇹🇷', 'tr', 'Türkçe', settings),
            const SizedBox(width: 8),
            _buildLanguageTile('🇬🇧', 'en', 'English', settings),
            const SizedBox(width: 8),
            _buildLanguageTile('🇩🇪', 'de', 'Deutsch', settings),
          ],
        ),
      ],
    );
  }

  Widget _buildOpacitySection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.visibility_outlined,
          '${settings.getTranslatedText('appearance', settings.language).toUpperCase()} - OPACITY',
          settings,
        ),
        const SizedBox(height: 16),
        _buildSliderRow(
          label: settings.getTranslatedText(
            'sidebar_opacity',
            settings.language,
          ),
          value: settings.sidebarOpacity,
          min: 0.0,
          max: 1.0,
          steps: 100,
          onChanged: (v) => settings.updateSettings(sidebarOpacity: v),
          hintLeft: settings.language == 'tr' ? 'Şeffaf' : 'Transparent',
          hintCenter: settings.language == 'tr' ? 'Yarı Saydam' : 'Semi-Opaque',
          hintRight: settings.language == 'tr' ? 'Opak' : 'Opaque',
          displayValue: '${(settings.sidebarOpacity * 100).toInt()}%',
          settings: settings,
        ),
      ],
    );
  }

  Widget _buildAutoHideSection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.timer_outlined,
          '${settings.getTranslatedText('appearance', settings.language).toUpperCase()} - AUTO HIDE',
          settings,
        ),
        const SizedBox(height: 16),
        (() {
          const autoHideOptions = [
            0.0,
            0.25,
            0.5,
            0.75,
            1.0,
            1.25,
            1.5,
            1.75,
            2.0,
            2.5,
            3.0,
            3.5,
            4.0,
            4.5,
            5.0,
            5.5,
            6.0,
            6.5,
            7.0,
            7.5,
            8.0,
            8.5,
            9.0,
            9.5,
            10.0,
            10.5,
            11.0,
            11.5,
            12.0,
            12.5,
            13.0,
            13.5,
            14.0,
            14.5,
            15.0,
          ];
          int currentIndex = autoHideOptions.indexOf(settings.autoHideDuration);
          if (currentIndex == -1) {
            double closest = 3.0;
            double minDiff = 999.0;
            for (var opt in autoHideOptions) {
              double diff = (opt - settings.autoHideDuration).abs();
              if (diff < minDiff) {
                minDiff = diff;
                closest = opt;
              }
            }
            currentIndex = autoHideOptions.indexOf(closest);
          }
          final String displayVal = settings.autoHideDuration == 0.0
              ? settings.getTranslatedText('off', settings.language)
              : '${settings.autoHideDuration}${settings.language == 'tr' ? 'sn' : 's'}';

          return _buildSliderRow(
            label: settings.getTranslatedText(
              'autohide_label',
              settings.language,
            ),
            value: currentIndex.toDouble(),
            min: 0,
            max: (autoHideOptions.length - 1).toDouble(),
            steps: autoHideOptions.length - 1,
            onChanged: (v) {
              final double selectedDuration = autoHideOptions[v.round()];
              settings.updateSettings(autoHideDuration: selectedDuration);
            },
            hintLeft: settings.getTranslatedText('off', settings.language),
            hintCenter: '2sn',
            hintRight: '15sn',
            displayValue: displayVal,
            settings: settings,
          );
        })(),
      ],
    );
  }

  Widget _buildIconColorSection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.palette_outlined,
          settings
              .getTranslatedText('icon_colors', settings.language)
              .toUpperCase(),
          settings,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildColorOption(
                    const Color(0xFF6366F1),
                    settings,
                  ), // Indigo
                  _buildColorOption(const Color(0xFFEC4899), settings), // Pink
                  _buildColorOption(const Color(0xFFF59E0B), settings), // Amber
                  _buildColorOption(
                    const Color(0xFF10B981),
                    settings,
                  ), // Emerald
                  _buildColorOption(const Color(0xFF3B82F6), settings), // Blue
                  _buildColorOption(const Color(0xFFEF4444), settings), // Red
                  _buildColorOption(
                    const Color(0xFF8B5CF6),
                    settings,
                  ), // Violet
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.getTranslatedText(
                          'live_preview',
                          settings.language,
                        ),
                        style: GoogleFonts.manrope(
                          color: const Color(0xFF9B92C9),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        settings.getTranslatedText(
                          'color_description',
                          settings.language,
                        ),
                        style: GoogleFonts.manrope(
                          color: const Color(0xFF9B92C9).withValues(alpha: 0.6),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D1933),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.home,
                          color: settings.primaryColor,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          settings.getTranslatedText(
                            'live_tv',
                            settings.language,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColorOption(Color color, SettingsProvider settings) {
    final isSelected = settings.primaryColor.toARGB32() == color.toARGB32();
    return GestureDetector(
      onTap: () => settings.updateSettings(primaryColor: color),
      child: AnimatedContainer(
        duration: Duration.zero,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 3,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 15,
                spreadRadius: 2,
              ),
          ],
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }

  Widget _buildAutoSaveHint(SettingsProvider settings) {
    return Opacity(
      opacity: 0.65,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 11,
          ),
          const SizedBox(width: 5),
          Text(
            settings.language == 'tr'
                ? 'Değişiklikler otomatik kaydedilir'
                : settings.language == 'de'
                    ? 'Änderungen werden automatisch gespeichert'
                    : 'Changes are saved automatically',
            style: const TextStyle(color: Colors.green, fontSize: 8),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCode(SettingsProvider settings) {
    final label = settings.language == 'tr'
        ? 'Cihaz Kodu'
        : settings.language == 'de'
            ? 'Gerätecode'
            : 'Device Code';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.perm_device_information_outlined,
            color: settings.primaryColor.withValues(alpha: 0.8),
            size: 13,
          ),
          const SizedBox(width: 7),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white54, fontSize: 9),
          ),
          Flexible(
            child: Text(
              LicenseService.deviceId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile(
    String label,
    IconData icon,
    String sub,
    bool isSelected,
    VoidCallback onTap,
    SettingsProvider settings,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration.zero,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? settings.primaryColor.withValues(alpha: 0.1)
                : const Color(0xFF292348).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? settings.primaryColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: isSelected
                          ? settings.primaryColor
                          : const Color(0xFF9B92C9),
                      size: 20,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        style: const TextStyle(
                          color: Color(0xFF9B92C9),
                          fontSize: 8,
                        ),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
              if (isSelected)
                Positioned(
                  right: 2,
                  top: 0,
                  child: Icon(
                    Icons.check_circle,
                    color: settings.primaryColor,
                    size: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageTile(
    String flag,
    String langCode,
    String label,
    SettingsProvider settings,
  ) {
    final isSelected = settings.language == langCode;
    return Expanded(
      child: GestureDetector(
        onTap: () => settings.updateSettings(language: langCode),
        child: AnimatedContainer(
          duration: Duration.zero,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? settings.primaryColor.withValues(alpha: 0.1)
                : const Color(0xFF292348).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? settings.primaryColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(flag, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Positioned(
                  right: 2,
                  top: 0,
                  child: Icon(
                    Icons.check_circle,
                    color: settings.primaryColor,
                    size: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    int? steps,
    required Function(double) onChanged,
    required String hintLeft,
    required String hintCenter,
    required String hintRight,
    String? displayValue,
    required SettingsProvider settings,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF292348),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                displayValue ?? '${(value * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            activeTrackColor: settings.primaryColor,
            inactiveTrackColor: const Color(0xFF292348),
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: steps,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              hintLeft,
              style: const TextStyle(color: Color(0xFF9B92C9), fontSize: 10),
            ),
            Text(
              hintCenter,
              style: const TextStyle(color: Color(0xFF9B92C9), fontSize: 10),
            ),
            Text(
              hintRight,
              style: const TextStyle(color: Color(0xFF9B92C9), fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}

class _HiddenCategoriesDialog extends StatefulWidget {
  const _HiddenCategoriesDialog({
    required this.settings,
    required this.profileId,
  });

  final SettingsProvider settings;
  final String? profileId;

  @override
  State<_HiddenCategoriesDialog> createState() =>
      _HiddenCategoriesDialogState();
}

class _HiddenCategoriesDialogState extends State<_HiddenCategoriesDialog> {
  final FocusNode _focusNode = FocusNode();
  int _focusedIndex = 0;

  List<({String type, String category})> get _items =>
      widget.settings.hiddenCategories(profileId: widget.profileId);

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

  String _typeLabel(String type) {
    switch (type) {
      case 'live':
        return _text('CANLI TV', 'LIVE TV', 'LIVE-TV');
      case 'movie':
        return _text('FİLM', 'MOVIE', 'FILM');
      case 'series':
        return _text('DİZİ', 'SERIES', 'SERIE');
      default:
        return type.toUpperCase();
    }
  }

  Future<void> _restoreFocused() async {
    final items = _items;
    if (items.isEmpty) return;
    final item = items[_focusedIndex.clamp(0, items.length - 1)];
    await widget.settings.setCategoryHidden(
      item.type,
      item.category,
      false,
      profileId: widget.profileId,
    );
    if (!mounted) return;
    setState(() {
      final remaining = _items.length;
      _focusedIndex =
          remaining == 0 ? 0 : _focusedIndex.clamp(0, remaining - 1);
    });
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
    final items = _items;
    if (items.isEmpty) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
          () => _focusedIndex = (_focusedIndex - 1).clamp(0, items.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(
          () => _focusedIndex = (_focusedIndex + 1).clamp(0, items.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _restoreFocused();
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (_, event) => _handleKey(event),
      child: Dialog(
        backgroundColor: const Color(0xFF171329),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          width: 520,
          height: 430,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text('GİZLİ KATEGORİLER', 'HIDDEN CATEGORIES',
                      'AUSGEBLENDETE KATEGORIEN'),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _text(
                    'Göstermek istediğiniz kategoride OK tuşuna basın.',
                    'Press OK on a category to show it again.',
                    'Drücken Sie OK, um eine Kategorie wieder anzuzeigen.',
                  ),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            _text(
                                'Gizlenmiş kategori yok',
                                'No hidden categories',
                                'Keine ausgeblendeten Kategorien'),
                            style: const TextStyle(color: Colors.white60),
                          ),
                        )
                      : ListView.builder(
                          itemCount: items.length,
                          itemExtent: 54,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final focused = index == _focusedIndex;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _focusedIndex = index);
                                _restoreFocused();
                              },
                              child: AnimatedContainer(
                                duration: Duration.zero,
                                margin: const EdgeInsets.only(bottom: 6),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: focused
                                      ? widget.settings.primaryColor
                                          .withValues(alpha: 0.18)
                                      : const Color(0xFF292348),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: focused
                                        ? widget.settings.primaryColor
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 74,
                                      child: Text(
                                        _typeLabel(item.type),
                                        style: TextStyle(
                                          color: widget.settings.primaryColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        item.category,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.visibility_rounded,
                                        color: Colors.white70, size: 19),
                                  ],
                                ),
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
