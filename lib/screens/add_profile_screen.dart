import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../models/profile.dart';
import '../widgets/local_companion_pairing_card.dart';

class AddProfileScreen extends StatefulWidget {
  final Profile? profileToEdit;

  const AddProfileScreen({super.key, this.profileToEdit});

  @override
  State<AddProfileScreen> createState() => _AddProfileScreenState();
}

class _AddProfileScreenState extends State<AddProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _urlFocus = FocusNode();
  bool _isNameActive = false;
  bool _isUrlActive = false;
  bool _isNameFocused = false;
  bool _isUrlFocused = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.profileToEdit?.name ?? '');
    _urlController =
        TextEditingController(text: widget.profileToEdit?.m3uUrl ?? '');

    _nameFocus.addListener(() {
      if (mounted) {
        setState(() {
          _isNameActive = _nameFocus.hasFocus ? _isNameActive : false;
          _isNameFocused = _nameFocus.hasFocus;
        });
      }
    });

    KeyEventResult handleNav(FocusNode node, KeyEvent event, bool isActive,
        VoidCallback onActivate) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          if (!isActive) {
            onActivate();
            return KeyEventResult.handled;
          }
        } else if (!isActive) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            node.focusInDirection(TraversalDirection.down);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            node.focusInDirection(TraversalDirection.up);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            node.focusInDirection(TraversalDirection.left);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            node.focusInDirection(TraversalDirection.right);
            return KeyEventResult.handled;
          }
        }
      }
      return KeyEventResult.ignored;
    }

    _nameFocus.onKeyEvent =
        (node, event) => handleNav(node, event, _isNameActive, _activateName);

    _urlFocus.addListener(() {
      if (mounted) {
        setState(() {
          _isUrlActive = _urlFocus.hasFocus ? _isUrlActive : false;
          _isUrlFocused = _urlFocus.hasFocus;
        });
      }
    });

    _urlFocus.onKeyEvent =
        (node, event) => handleNav(node, event, _isUrlActive, _activateUrl);
  }

  void _activateName() {
    setState(() => _isNameActive = true);
    _nameFocus.requestFocus();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  void _activateUrl() {
    setState(() => _isUrlActive = true);
    _urlFocus.requestFocus();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  String get _initials {
    final text = _nameController.text.trim();
    if (text.isEmpty) return 'YK';
    if (text.length == 1) return text.toUpperCase();
    return text.substring(0, 2).toUpperCase();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _nameFocus.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir kullanıcı adı girin')),
      );
      return;
    }

    final playlistUrl = _urlController.text.trim();
    final uri = Uri.tryParse(playlistUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Geçerli bir http:// veya https:// oynatma listesi adresi girin'),
        ),
      );
      _urlFocus.requestFocus();
      return;
    }

    final profile = Profile(
      id: widget.profileToEdit?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      initial: _initials,
      m3uUrl: playlistUrl,
      // Preserve other fields if editing
      colorIndex: widget.profileToEdit?.colorIndex ?? 0,
    );

    Navigator.pop(context, profile);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.profileToEdit != null;
    final windowSize = MediaQuery.sizeOf(context);
    final compactLayout = windowSize.height < 700 || windowSize.width < 1100;
    return PopScope(
      canPop: !(_isNameActive || _isUrlActive),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        // If the user pressed back while editing, just close the keyboard and keep focus
        if (_isNameActive) {
          setState(() => _isNameActive = false);
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          _nameFocus.requestFocus();
        } else if (_isUrlActive) {
          setState(() => _isUrlActive = false);
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          _urlFocus.requestFocus();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compactLayout ? 32 : 80,
              vertical: compactLayout ? 20 : 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Profili Düzenle' : 'Yeni Kullanıcı Ekle',
                  style: GoogleFonts.splineSans(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEditing
                      ? 'Profil bilgilerini güncelleyin.'
                      : 'Profilinizi oluşturun ve içerik kaynağını ekleyin.',
                  style: GoogleFonts.notoSans(
                    fontSize: 16,
                    color: Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: LayoutBuilder(
                          builder: (context, paneConstraints) {
                            return SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: paneConstraints.maxHeight,
                                ),
                                child: IntrinsicHeight(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Kullanıcı Adı', style: _labelStyle),
                                      const SizedBox(height: 8),
                                      AnimatedContainer(
                                        duration: Duration.zero,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: _isNameActive
                                                ? AppColors.primary
                                                : _isNameFocused
                                                    ? Colors.white
                                                    : Colors.transparent,
                                            width:
                                                _isNameFocused || _isNameActive
                                                    ? 2
                                                    : 0,
                                          ),
                                        ),
                                        child: TextField(
                                          controller: _nameController,
                                          focusNode: _nameFocus,
                                          readOnly: !_isNameActive,
                                          onTap: _activateName,
                                          onSubmitted: (_) {
                                            setState(
                                                () => _isNameActive = false);
                                            SystemChannels.textInput
                                                .invokeMethod('TextInput.hide');
                                            _nameFocus.requestFocus();
                                          },
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14),
                                          decoration: _inputDecoration(
                                              'Örn. Ahmet Yılmaz',
                                              Icons.person),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text('İçerik Kaynağı (M3U)',
                                            style: _labelStyle),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1B2E),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.05)),
                                        ),
                                        child: Column(
                                          children: [
                                            AnimatedContainer(
                                              duration: Duration.zero,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: _isUrlActive
                                                      ? AppColors.primary
                                                      : _isUrlFocused
                                                          ? Colors.white
                                                          : Colors.transparent,
                                                  width: _isUrlFocused ||
                                                          _isUrlActive
                                                      ? 2
                                                      : 0,
                                                ),
                                              ),
                                              child: TextField(
                                                controller: _urlController,
                                                focusNode: _urlFocus,
                                                readOnly: !_isUrlActive,
                                                onTap: _activateUrl,
                                                onSubmitted: (_) {
                                                  setState(() =>
                                                      _isUrlActive = false);
                                                  SystemChannels.textInput
                                                      .invokeMethod(
                                                          'TextInput.hide');
                                                  _urlFocus.requestFocus();
                                                },
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14),
                                                decoration: InputDecoration(
                                                  hintText: 'https://...',
                                                  hintStyle: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 14),
                                                  border: InputBorder.none,
                                                  prefixIcon: const Icon(
                                                      Icons.link,
                                                      color: Colors.grey,
                                                      size: 20),
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          vertical: 12),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    Colors.grey[400],
                                                side: BorderSide(
                                                    color: Colors.grey[700]!),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 16),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12)),
                                              ),
                                              child: const Text('VAZGEÇ',
                                                  style:
                                                      TextStyle(fontSize: 16)),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _handleSave,
                                              icon: Icon(
                                                  isEditing
                                                      ? Icons.save
                                                      : Icons.check,
                                                  size: 20),
                                              label: Text(
                                                  isEditing
                                                      ? 'KAYDET'
                                                      : 'OLUŞTUR',
                                                  style: const TextStyle(
                                                      fontSize: 16)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.primary,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 16),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12)),
                                                elevation: 0,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(width: compactLayout ? 28 : 60),
                      Expanded(
                        flex: 1,
                        child: SingleChildScrollView(
                          child: isEditing
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 160,
                                      height: 160,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            AppColors.primary,
                                            AppColors.primary
                                                .withValues(alpha: 0.8),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.4),
                                            blurRadius: 30,
                                            offset: const Offset(0, 15),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: AnimatedBuilder(
                                          animation: _nameController,
                                          builder: (context, child) {
                                            return Text(
                                              _initials,
                                              style: GoogleFonts.splineSans(
                                                fontSize: 64,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      _nameController.text.isEmpty
                                          ? (isEditing
                                              ? 'Kullanıcı'
                                              : 'Yeni Kullanıcı')
                                          : _nameController.text,
                                      style: GoogleFonts.notoSans(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                )
                              : LocalCompanionPairingCard(
                                  onProfileReceived: (profile) {
                                    if (mounted) {
                                      Navigator.pop(context, profile);
                                    }
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle get _labelStyle => GoogleFonts.notoSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.grey[400],
      );

  InputDecoration _inputDecoration(String hint, IconData suffixIcon) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFF1E1B2E),
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[600]),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1),
      ),
      suffixIcon: Icon(suffixIcon, color: Colors.grey[500]),
    );
  }
}
