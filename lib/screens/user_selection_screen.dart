import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/profile.dart';
import '../theme/app_colors.dart';
import 'add_profile_screen.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_overlay.dart';
import '../utils/instant_dialog.dart';
import 'package:provider/provider.dart';
import '../providers/channel_provider.dart';

class UserSelectionScreen extends StatefulWidget {
  const UserSelectionScreen({super.key});

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen> {
  SettingsProvider get _settings => context.read<SettingsProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_settings.profiles.isEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AddProfileScreen()),
        ).then((profile) {
          if (profile != null && profile is Profile) {
            _addNewProfile(profile);
          }
        });
      }
    });
  }

  Future<void> _addNewProfile(Profile profile) async {
    await _settings.saveProfile(profile);
    await _settings.setLastState(profileId: profile.id, screen: 'home');
  }

  Future<void> _deleteProfile(String id) async {
    await _settings.deleteProfile(id);
    if (!mounted) return;
    await context.read<ChannelProvider>().loadProfiles(_settings.profiles);
  }

  Future<void> _handleEditProfile(Profile updatedProfile) async {
    await _settings.saveProfile(updatedProfile);
    if (!mounted) return;
    await context.read<ChannelProvider>().loadProfiles(_settings.profiles);
  }

  Future<void> _editProfile(Profile profile) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddProfileScreen(profileToEdit: profile),
      ),
    );

    if (result != null && result is Profile) {
      await _handleEditProfile(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.backgroundDark,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Background Image
              Opacity(
                opacity: 0.1,
                child: Image.network(
                  'https://images.unsplash.com/photo-1535356976722-6ee29f40e062?q=80&w=2070&auto=format&fit=crop',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Container(color: Colors.black),
                ),
              ),
              // Gradient Overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.backgroundDark.withValues(alpha: 0.9),
                      AppColors.backgroundDark.withValues(alpha: 0.95),
                      AppColors.backgroundDark,
                    ],
                  ),
                ),
              ),
              // Content
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32.0,
                    vertical: 24.0,
                  ),
                  child: Column(
                    children: [
                      // Header
                      _buildHeader(),
                      const SizedBox(height: 48),
                      // Main Content
                      Text(
                        _settings.getText('who_watching'),
                        style: GoogleFonts.splineSans(
                          fontSize: 48,
                          fontWeight: FontWeight.w300,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      _buildProfilesRow(),
                      const SizedBox(height: 48),
                      // Footer
                      const Text(
                        'TIVUQIPTV Premium Experience v2.5.0',
                        style: TextStyle(fontSize: 12, color: Colors.white24),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _settings.primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'TIVUQ',
                    style: GoogleFonts.splineSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Colors.white,
                    ),
                  ),
                  TextSpan(
                    text: 'IPTV',
                    style: GoogleFonts.splineSans(
                      fontWeight: FontWeight.bold,
                      color: _settings.primaryColor,
                      fontSize: 24,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        IconButton(
          onPressed: () => _showSettings(context),
          icon: const Icon(Icons.settings, color: Colors.white60),
        ),
      ],
    );
  }

  void _showSettings(BuildContext context) {
    showInstantDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => const SettingsOverlay(),
    );
  }

  Widget _buildProfilesRow() {
    return Wrap(
      spacing: 48,
      runSpacing: 48,
      alignment: WrapAlignment.center,
      children: [
        ..._settings.profiles.asMap().entries.map(
              (entry) => _ProfileCard(
                profile: entry.value,
                autoFocus: entry.key == 0,
                onDelete: _deleteProfile,
                onEdit: _editProfile,
              ),
            ),
        _AddProfileCard(
          onProfileAdded: _addNewProfile,
          autoFocus: _settings.profiles.isEmpty,
        ),
      ],
    );
  }
}

class _ProfileCard extends StatefulWidget {
  final Profile profile;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(Profile) onEdit;
  final bool autoFocus;

  const _ProfileCard({
    required this.profile,
    required this.onDelete,
    required this.onEdit,
    this.autoFocus = false,
  });

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _isHovered = false;
  bool _isFocused = false;
  final _settings = SettingsProvider();
  final FocusNode _editFocusNode = FocusNode();

  @override
  void dispose() {
    _editFocusNode.dispose();
    super.dispose();
  }

  void _showContextMenu(BuildContext context, Offset globalPosition) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF1E1933),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          onTap: () => widget.onEdit(widget.profile),
          child: Row(
            children: [
              const Icon(Icons.edit, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Text(
                _settings.language == 'tr'
                    ? 'Düzenle'
                    : (_settings.language == 'en' ? 'Edit' : 'Bearbeiten'),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () => widget.onDelete(widget.profile.id),
          child: Row(
            children: [
              const Icon(Icons.delete, color: Colors.red, size: 20),
              const SizedBox(width: 12),
              Text(
                _settings.language == 'tr'
                    ? 'Sil'
                    : (_settings.language == 'en' ? 'Delete' : 'Löschen'),
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleTap() async {
    final playlistUrl = widget.profile.m3uUrl?.trim() ?? '';
    if (playlistUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu profilin oynatma listesi adresi eksik.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (playlistUrl.isNotEmpty) {
      showInstantDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final channelProvider = Provider.of<ChannelProvider>(
        context,
        listen: false,
      );
      await channelProvider.loadProfiles(_settings.profiles);

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (channelProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _settings.language == 'tr'
                  ? 'Oynatma listesi yüklenemedi: ${channelProvider.error}'
                  : 'Failed to load playlist: ${channelProvider.error}',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (channelProvider.channels.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _settings.language == 'tr'
                  ? 'Oynatma listesi boş veya geçersiz.'
                  : 'Playlist is empty or invalid.',
            ),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }
    }

    if (mounted) {
      _settings.setLastState(profileId: widget.profile.id, screen: 'live_tv');
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = (_isHovered || _isFocused) ? 1.1 : 1.0;
    final borderColor = (_isHovered || _isFocused)
        ? _settings.primaryColor
        : Colors.transparent;
    final boxShadow = (_isHovered || _isFocused)
        ? [
            BoxShadow(
              color: _settings.primaryColor.withValues(alpha: 0.4),
              blurRadius: 40,
              spreadRadius: 0,
            ),
          ]
        : <BoxShadow>[];

    return Column(
      children: [
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () {
              _editFocusNode.requestFocus();
            },
          },
          child: FocusableActionDetector(
            autofocus: widget.autoFocus,
            onShowFocusHighlight: (fullscreen) =>
                setState(() => _isFocused = fullscreen),
            onShowHoverHighlight: (hovered) =>
                setState(() => _isHovered = hovered),
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (intent) {
                  _handleTap();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              onTap: _handleTap,
              onLongPressStart: (details) =>
                  _showContextMenu(context, details.globalPosition),
              onSecondaryTapUp: (details) =>
                  _showContextMenu(context, details.globalPosition),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: Duration.zero,
                    transform: Matrix4.identity()
                      ..scaleByDouble(scale, scale, scale, 1),
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor, width: 4),
                      boxShadow: boxShadow,
                    ),
                    child: Center(
                      child: Text(
                        widget.profile.initial,
                        style: GoogleFonts.splineSans(
                          fontSize: 60,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.profile.name,
                    style: GoogleFonts.notoSans(
                      fontSize: 20,
                      color: (_isHovered || _isFocused)
                          ? Colors.white
                          : Colors.grey[400],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          focusNode: _editFocusNode,
          onPressed: () => widget.onEdit(widget.profile),
          icon: const Icon(Icons.edit_outlined, size: 17),
          label: Text(
            _settings.language == 'tr'
                ? 'Düzenle'
                : (_settings.language == 'en' ? 'Edit' : 'Bearbeiten'),
          ),
        ),
      ],
    );
  }
}

class _AddProfileCard extends StatefulWidget {
  final Function(Profile) onProfileAdded;
  final bool autoFocus;

  const _AddProfileCard({required this.onProfileAdded, this.autoFocus = false});

  @override
  State<_AddProfileCard> createState() => _AddProfileCardState();
}

class _AddProfileCardState extends State<_AddProfileCard> {
  bool _isHovered = false;
  bool _isFocused = false;
  final _settings = SettingsProvider();

  Future<void> _handleTap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddProfileScreen()),
    );

    if (result != null && result is Profile) {
      widget.onProfileAdded(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = (_isHovered || _isFocused) ? 1.1 : 1.0;
    final borderColor =
        (_isHovered || _isFocused) ? Colors.white : Colors.grey[600]!;
    final bgColor =
        (_isHovered || _isFocused) ? AppColors.surfaceDark : Colors.transparent;

    return FocusableActionDetector(
      autofocus: widget.autoFocus,
      onShowFocusHighlight: (fullscreen) =>
          setState(() => _isFocused = fullscreen),
      onShowHoverHighlight: (hovered) => setState(() => _isHovered = hovered),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            _handleTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: _handleTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: Duration.zero,
              transform: Matrix4.identity()
                ..scaleByDouble(scale, scale, scale, 1),
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 4),
              ),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: 48,
                  color: (_isHovered || _isFocused)
                      ? Colors.white
                      : Colors.grey[500],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _settings.language == 'tr'
                  ? 'Profil Ekle'
                  : (_settings.language == 'en'
                      ? 'Add Profile'
                      : 'Profil hinzufügen'),
              style: GoogleFonts.notoSans(
                fontSize: 20,
                color: (_isHovered || _isFocused)
                    ? Colors.white
                    : Colors.grey[400],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
