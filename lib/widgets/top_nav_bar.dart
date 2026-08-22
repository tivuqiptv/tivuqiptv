import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/profile.dart';
import '../providers/settings_provider.dart';
import '../screens/live_tv_screen.dart';
import '../screens/movies_screen.dart';
import '../screens/series_screen.dart';
import '../screens/user_selection_screen.dart';
import '../services/player_engine.dart';

class TopNavBar extends StatefulWidget {
  final String activeScreen; // 'live_tv', 'movies', 'series'
  final VoidCallback? onDismiss;

  const TopNavBar({super.key, required this.activeScreen, this.onDismiss});

  @override
  State<TopNavBar> createState() => TopNavBarState();
}

class TopNavBarState extends State<TopNavBar> {
  bool _isExpanded = false;
  bool _isNavigating = false;
  Timer? _hideTimer;

  bool get isExpanded => _isExpanded;

  void expandForRemote([double? durationSeconds]) {
    setState(() {
      _isExpanded = true;
      _focusedIndex = _screenNames.indexOf(widget.activeScreen);
      if (_focusedIndex < 0) _focusedIndex = 0;
    });
    final sec = (durationSeconds != null && durationSeconds > 0)
        ? durationSeconds
        : 3.0;
    _startHideTimer(sec);
  }

  void collapse() {
    _hideTimer?.cancel();
    if (mounted) {
      setState(() => _isExpanded = false);
      widget.onDismiss?.call();
    }
  }

  // Remote navigation support
  static const List<String> _screenNames = ['live_tv', 'movies', 'series'];
  int _focusedIndex = 0;
  bool get isFocused => _isExpanded;

  void navigateLeft([double? durationSeconds]) {
    setState(() {
      if (_focusedIndex > 0) _focusedIndex--;
    });
    final sec = (durationSeconds != null && durationSeconds > 0)
        ? durationSeconds
        : 3.0;
    _startHideTimer(sec);
  }

  void navigateRight([double? durationSeconds]) {
    setState(() {
      if (_focusedIndex < _screenNames.length - 1) _focusedIndex++;
    });
    final sec = (durationSeconds != null && durationSeconds > 0)
        ? durationSeconds
        : 3.0;
    _startHideTimer(sec);
  }

  void selectCurrent(BuildContext _) {
    _navigateTo(_screenNames[_focusedIndex]);
  }

  void _startHideTimer(double seconds) {
    _hideTimer?.cancel();
    if (seconds <= 0) return;
    _hideTimer = Timer(Duration(milliseconds: (seconds * 1000).toInt()), () {
      if (mounted) {
        setState(() => _isExpanded = false);
        widget.onDismiss?.call();
      }
    });
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> _navigateTo(String screenName) async {
    if (widget.activeScreen == screenName || _isNavigating) return;
    _isNavigating = true;

    final settings = Provider.of<SettingsProvider>(context, listen: false);

    if (widget.activeScreen == 'live_tv' && screenName != 'live_tv') {
      await AppPlayerEngine.restoreDisplayModeAndWait();
    } else if (widget.activeScreen != 'live_tv' && screenName == 'live_tv') {
      await AppPlayerEngine.prepareLiveDisplayModeAndWait(
        refreshRate: settings.liveTvRefreshRate,
      );
    }
    if (!mounted) return;

    settings.setLastState(screen: screenName);

    final profileId = settings.lastProfileId;
    Profile? currentProfile;
    for (final profile in settings.profiles) {
      if (profile.id == profileId) {
        currentProfile = profile;
        break;
      }
    }
    if (currentProfile == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const UserSelectionScreen()),
      );
      _isNavigating = false;
      return;
    }

    Widget target;
    if (screenName == 'live_tv') {
      target = const LiveTVScreen();
    } else if (screenName == 'movies') {
      target = MoviesScreen(profile: currentProfile);
    } else {
      target = SeriesScreen(profile: currentProfile);
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation1, animation2) => target,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    _isNavigating = false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Invisible Hover Trigger Zone: Top 15px of screen
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 15,
          child: MouseRegion(
            onEnter: (_) {
              _cancelHideTimer();
              setState(() => _isExpanded = true);
            },
            child: const SizedBox.expand(),
          ),
        ),

        // Animated Nav Bar Container
        AnimatedPositioned(
          duration: Duration.zero,
          curve: Curves.easeOutCubic,
          top: _isExpanded ? 16 : -80, // Hides off screen when collapsed
          left: 0,
          right: 0,
          child: Center(
            child: MouseRegion(
              onEnter: (_) {
                _cancelHideTimer();
                setState(() => _isExpanded = true);
              },
              onExit: (_) {
                final double duration = settings.autoHideDuration > 0.0
                    ? settings.autoHideDuration
                    : 3.0;
                _startHideTimer(duration);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF131022)
                      .withValues(alpha: settings.sidebarOpacity),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: Colors.white
                          .withValues(alpha: 0.08 * settings.sidebarOpacity)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: 0.5 * settings.sidebarOpacity),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildNavButton(
                            settings.getText('live_tv'), 'live_tv', settings),
                        _buildDivider(),
                        _buildNavButton(
                            settings.getText('movies'), 'movies', settings),
                        _buildDivider(),
                        _buildNavButton(
                            settings.getText('series'), 'series', settings),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavButton(
      String title, String screenName, SettingsProvider settings) {
    final bool isActive = widget.activeScreen == screenName;
    final bool isFocusedItem =
        _isExpanded && _screenNames[_focusedIndex] == screenName;
    return GestureDetector(
      onTap: () => _navigateTo(screenName),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Duration.zero,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: isFocusedItem
                ? Colors.white.withValues(alpha: 0.2 * settings.sidebarOpacity)
                : (isActive
                    ? settings.primaryColor
                        .withValues(alpha: 0.15 * settings.sidebarOpacity)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(20),
            border: isFocusedItem
                ? Border.all(color: Colors.white, width: 2)
                : null,
          ),
          child: Text(
            title,
            style: GoogleFonts.splineSans(
              fontSize: 14,
              fontWeight: (isActive || isFocusedItem)
                  ? FontWeight.bold
                  : FontWeight.w500,
              color:
                  (isActive || isFocusedItem) ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 16,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white.withValues(alpha: 0.12),
    );
  }
}
