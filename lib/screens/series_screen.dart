import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../models/profile.dart';
import '../utils/scoped_category.dart';
import 'package:provider/provider.dart';
import '../providers/channel_provider.dart';
import '../models/channel.dart';
import 'user_selection_screen.dart';
import '../widgets/settings_overlay.dart';
import '../utils/instant_dialog.dart';
import '../widgets/series_episodes_dialog.dart';
import '../providers/settings_provider.dart';
import '../providers/watch_history_provider.dart';
import '../widgets/top_nav_bar.dart';
import '../services/metadata_service.dart';
import '../utils/remote_long_press.dart';
import '../utils/parental_category_access.dart';

class SeriesScreen extends StatefulWidget {
  final Profile profile;
  const SeriesScreen({super.key, required this.profile});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

enum _RemoteMode {
  sidebarProfiles,
  sidebarCategories,
  sidebarSearch,
  sidebarSeries,
  mainContent,
  topNav,
  sidebarHeader,
  sidebarFooter,
}

class _SeriesScreenState extends State<SeriesScreen> {
  static const double _sidebarWidth = 256;
  static const double _sidebarItemExtent = 42;
  static const double _categoryItemExtent = 50;
  static const String _recentlyWatchedCategory = 'Son İzlenenler';
  static const String _newlyAddedCategory = 'Son Eklenenler';

  _RemoteMode _remoteMode = _RemoteMode.sidebarSeries;
  DateTime? _topNavOpenedAt;
  DateTime? _lastModalClosedAt;
  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final GlobalKey<TopNavBarState> _topNavKey = GlobalKey<TopNavBarState>();
  String _selectedCategory = 'Tümü';
  String _searchQuery = '';
  int _selectedSeriesIndex = 0;
  bool _showCategoriesSidebar = false;
  bool _showProfilesSidebar = false;
  final _settings = SettingsProvider();
  final RemoteLongPress _favoriteLongPress = RemoteLongPress();
  final RemoteLongPress _categoryLongPress = RemoteLongPress();
  MovieMetadata? _currentMetadata;
  bool _isLoadingMetadata = false;
  int _metadataFetchId = 0;
  Timer? _metadataDebounce;

  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _categorySidebarScrollController = ScrollController();
  final ScrollController _profileSidebarScrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();
  final Map<String, GlobalKey> _categoryKeys = {};
  final Map<String, GlobalKey> _categorySidebarKeys = {};

  List<String> _categories = ['Tümü', 'Favoriler'];
  List<Channel> _series = [];
  List<Channel> _filteredSeries = const [];
  Map<String, int> _categoryCounts = const {};

  late Profile _currentProfile;
  ChannelProvider? _channelProvider;
  WatchHistoryProvider? _historyProvider;
  int _lastHistoryRevision = 0;
  String? _selectedProfileId;
  int _focusedProfileIndex = 0;

  bool get _hasMultipleProfiles => _settings.profiles.length > 1;
  List<Profile?> get _profileFilters => <Profile?>[
        null,
        ..._settings.profiles,
      ];

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    _settings.setLastState(screen: 'series');
    HardwareKeyboard.instance.addHandler(_handleGlobalHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ChannelProvider>(context, listen: false);
      _channelProvider = provider;
      provider.addListener(_handleCatalogChanged);
      _historyProvider = Provider.of<WatchHistoryProvider>(
        context,
        listen: false,
      );
      _lastHistoryRevision = _historyProvider!.recentRevision;
      _historyProvider!.addListener(_handleHistoryChanged);
      _updateCategories(provider.uniqueSeries);
    });
  }

  void _handleCatalogChanged() {
    if (!mounted || _channelProvider == null) return;
    _updateCategories(_channelProvider!.uniqueSeries);
  }

  void _handleHistoryChanged() {
    final history = _historyProvider;
    if (!mounted || history == null) return;
    if (history.recentRevision == _lastHistoryRevision) return;
    _lastHistoryRevision = history.recentRevision;
    _updateCategories(_series);
  }

  @override
  void dispose() {
    _favoriteLongPress.cancel();
    _categoryLongPress.cancel();
    _metadataDebounce?.cancel();
    _channelProvider?.removeListener(_handleCatalogChanged);
    _historyProvider?.removeListener(_handleHistoryChanged);
    HardwareKeyboard.instance.removeHandler(_handleGlobalHardwareKey);
    _keyboardFocusNode.dispose();
    _searchFocusNode.dispose();
    _categoryScrollController.dispose();
    _categorySidebarScrollController.dispose();
    _profileSidebarScrollController.dispose();
    _sidebarScrollController.dispose();
    super.dispose();
  }

  bool _handleGlobalHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.contextMenu ||
            key == LogicalKeyboardKey.f1)) {
      _showSettings(context);
      return true;
    }
    return false;
  }

  void _loadMetadata(String title, String category) async {
    if (!mounted) return;
    final int currentFetchId = ++_metadataFetchId;
    setState(() {
      _isLoadingMetadata = true;
      _currentMetadata = null;
    });
    final meta = await MetadataService.fetchMetadata(title, category);
    if (mounted && _metadataFetchId == currentFetchId) {
      setState(() {
        _currentMetadata = meta;
        _isLoadingMetadata = false;
      });
    }
  }

  void _scheduleMetadataLoad(String title, String category) {
    _metadataDebounce?.cancel();
    _metadataDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _loadMetadata(title, category),
    );
  }

  void _updateCategories(List<Channel> channels) {
    if (_selectedProfileId != null &&
        !_settings.profiles.any(
          (profile) => profile.id == _selectedProfileId,
        )) {
      _selectedProfileId = null;
    }
    setState(() {
      _series = channels;
      final profileSeries =
          channels.where(_matchesSelectedProfile).toList(growable: false);
      final cats = profileSeries
          .map((c) => c.category)
          .where(
            (cat) =>
                cat != 'Tümü' &&
                cat != 'Favoriler' &&
                cat != _recentlyWatchedCategory &&
                cat != _newlyAddedCategory &&
                !_settings.isCategoryHidden(
                  'series',
                  categoryLabel(cat),
                  profileId: categoryProfileId(cat),
                ),
          )
          .toSet()
          .toList();
      _categories = [
        'Tümü',
        'Favoriler',
        _recentlyWatchedCategory,
        _newlyAddedCategory,
        ...cats,
      ];
      _categoryCounts = _buildCategoryCounts(profileSeries);
      if (!_categories.contains(_selectedCategory)) {
        _selectedCategory = 'Tümü';
      }
      _filteredSeries = _computeFilteredSeries();
      if (_selectedSeriesIndex >= _filteredSeries.length) {
        _selectedSeriesIndex = 0;
      }
    });
    if (_filteredSeries.isNotEmpty) {
      _loadMetadata(
        _filteredSeries[_selectedSeriesIndex].name,
        _filteredSeries[_selectedSeriesIndex].category,
      );
    }
    _scrollToSelectedCategory();
  }

  bool _matchesSelectedProfile(Channel series) =>
      _selectedProfileId == null ||
      series.sourceProfileId == _selectedProfileId;

  Map<String, int> _buildCategoryCounts(List<Channel> channels) {
    channels = channels
        .where(
          (series) =>
              _matchesSelectedProfile(series) &&
              !_settings.isCategoryHidden(
                'series',
                categoryLabel(series.category),
                profileId: series.sourceProfileId,
              ),
        )
        .toList(growable: false);
    final counts = <String, int>{
      'Tümü': channels.length,
      'Favoriler': 0,
      _recentlyWatchedCategory: 0,
      _newlyAddedCategory: 0,
    };
    final history = Provider.of<WatchHistoryProvider>(context, listen: false);
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(const Duration(days: 7));
    final latestAllowed = now.add(const Duration(days: 1));
    for (final series in channels) {
      counts[series.category] = (counts[series.category] ?? 0) + 1;
      if (_settings.isFavorite(
        'series',
        series.id,
        profileId: series.sourceProfileId,
      )) {
        counts['Favoriler'] = (counts['Favoriler'] ?? 0) + 1;
      }
      if (history.getLastWatchedAt(
            _seriesHistoryId(series),
            profileId: series.sourceProfileId ?? _currentProfile.id,
          ) !=
          null) {
        counts[_recentlyWatchedCategory] =
            (counts[_recentlyWatchedCategory] ?? 0) + 1;
      }
      final addedAt = series.addedAt;
      if (addedAt != null &&
          !addedAt.isBefore(cutoff) &&
          !addedAt.isAfter(latestAllowed)) {
        counts[_newlyAddedCategory] = (counts[_newlyAddedCategory] ?? 0) + 1;
      }
    }
    return counts;
  }

  String _getCategoryKey(String cat) {
    if (cat == 'Tümü') return 'all';
    if (cat == 'Favoriler') return 'favorites_cat';
    if (cat == _recentlyWatchedCategory) return 'recently_watched';
    if (cat == _newlyAddedCategory) return 'newly_added';
    return cat;
  }

  void _scrollToSelectedCategory() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final key = _categoryKeys[_selectedCategory];
        if (key != null && key.currentContext != null) {
          Scrollable.ensureVisible(
            key.currentContext!,
            duration: Duration.zero,
            alignment: 0.5,
            curve: Curves.easeInOut,
          );
        }
      } catch (e) {
        debugPrint('Centering category failed: $e');
      }
    });
  }

  void _scrollToSelectedCategoryInSidebar() {
    if (_centerSelectedSidebarCategory()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerSelectedSidebarCategory();
    });
  }

  bool _centerSelectedSidebarCategory() {
    if (!_categorySidebarScrollController.hasClients) return false;
    final index = _categories.indexOf(_selectedCategory);
    if (index < 0) return false;
    final position = _categorySidebarScrollController.position;
    final target = index * _categoryItemExtent -
        (position.viewportDimension - _categoryItemExtent) / 2;
    _categorySidebarScrollController.jumpTo(
      target.clamp(0.0, position.maxScrollExtent),
    );
    return true;
  }

  void _scrollToProfileIndex(int index) {
    void center() {
      if (!mounted || !_profileSidebarScrollController.hasClients) return;
      final position = _profileSidebarScrollController.position;
      final target = index * _categoryItemExtent -
          (position.viewportDimension - _categoryItemExtent) / 2;
      _profileSidebarScrollController.jumpTo(
        target.clamp(0.0, position.maxScrollExtent),
      );
    }

    center();
    WidgetsBinding.instance.addPostFrameCallback((_) => center());
  }

  void _activateFocusedProfile() {
    final profiles = _profileFilters;
    if (_focusedProfileIndex < 0 || _focusedProfileIndex >= profiles.length) {
      return;
    }
    _selectedProfileId = profiles[_focusedProfileIndex]?.id;
    _selectedCategory = 'Tümü';
    _selectedSeriesIndex = 0;
    _searchQuery = '';
    _searchFocusNode.unfocus();
    _updateCategories(_series);
    setState(() {
      _showProfilesSidebar = false;
      _showCategoriesSidebar = true;
      _remoteMode = _RemoteMode.sidebarCategories;
    });
    _scrollToSelectedCategoryInSidebar();
  }

  int _profileSeriesCount(String? profileId) {
    return _series.where((series) {
      if (profileId != null && series.sourceProfileId != profileId) {
        return false;
      }
      return !_settings.isCategoryHidden(
        'series',
        categoryLabel(series.category),
        profileId: series.sourceProfileId,
      );
    }).length;
  }

  List<Channel> _computeFilteredSeries() {
    final visibleSeries = _series
        .where(
          (series) =>
              _matchesSelectedProfile(series) &&
              !_settings.isCategoryHidden(
                'series',
                categoryLabel(series.category),
                profileId: series.sourceProfileId,
              ),
        )
        .toList(growable: false);
    List<Channel> result;
    if (_selectedCategory == _recentlyWatchedCategory) {
      result = _recentlyWatchedSeries();
    } else if (_selectedCategory == _newlyAddedCategory) {
      result = _newlyAddedSeries();
    } else {
      result = visibleSeries.where((series) {
        if (_selectedCategory == 'Tümü') return true;
        if (_selectedCategory == 'Favoriler') {
          return _settings.isFavorite(
            'series',
            series.id,
            profileId: series.sourceProfileId,
          );
        }
        return series.category == _selectedCategory;
      }).toList();
    }

    result = result
        .where(
          (series) => !_settings.isCategoryHidden(
            'series',
            categoryLabel(series.category),
            profileId: series.sourceProfileId,
          ),
        )
        .toList(growable: false);

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result
          .where((series) => series.name.toLowerCase().contains(query))
          .toList();
    }
    return result;
  }

  String _seriesHistoryId(Channel series) => 'series:${series.id}';

  List<Channel> _recentlyWatchedSeries() {
    final history = Provider.of<WatchHistoryProvider>(context, listen: false);
    final result = _series
        .where(
          (series) =>
              _matchesSelectedProfile(series) &&
              history.getLastWatchedAt(
                    _seriesHistoryId(series),
                    profileId: series.sourceProfileId ?? _currentProfile.id,
                  ) !=
                  null &&
              !_settings.isCategoryHidden(
                'series',
                categoryLabel(series.category),
                profileId: series.sourceProfileId,
              ),
        )
        .toList()
      ..sort((a, b) {
        final aDate = history.getLastWatchedAt(
          _seriesHistoryId(a),
          profileId: a.sourceProfileId ?? _currentProfile.id,
        )!;
        final bDate = history.getLastWatchedAt(
          _seriesHistoryId(b),
          profileId: b.sourceProfileId ?? _currentProfile.id,
        )!;
        return bDate.compareTo(aDate);
      });
    return result.take(50).toList(growable: false);
  }

  List<Channel> _newlyAddedSeries() {
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(const Duration(days: 7));
    final latestAllowed = now.add(const Duration(days: 1));
    final result = _series.where((series) {
      final date = series.addedAt;
      return _matchesSelectedProfile(series) &&
          !_settings.isCategoryHidden(
            'series',
            categoryLabel(series.category),
            profileId: series.sourceProfileId,
          ) &&
          date != null &&
          !date.isBefore(cutoff) &&
          !date.isAfter(latestAllowed);
    }).toList()
      ..sort((a, b) => b.addedAt!.compareTo(a.addedAt!));
    return result;
  }

  void _changeSeries(int index) {
    setState(() {
      _selectedSeriesIndex = index;
    });
    final series = _filteredSeries[index];
    _scheduleMetadataLoad(series.name, series.category);
  }

  void _toggleSelectedSeriesFavorite() {
    final filtered = _filteredSeries;
    if (filtered.isEmpty || _selectedSeriesIndex >= filtered.length) return;
    final series = filtered[_selectedSeriesIndex];
    unawaited(
      _settings.toggleFavorite(
        'series',
        series.id,
        profileId: series.sourceProfileId,
      ),
    );
    setState(() {
      _categoryCounts = _buildCategoryCounts(_series);
      _filteredSeries = _computeFilteredSeries();
      if (_selectedCategory == 'Favoriler') {
        if (_selectedSeriesIndex >= _filteredSeries.length &&
            _filteredSeries.isNotEmpty) {
          _selectedSeriesIndex = _filteredSeries.length - 1;
        }
      }
    });
  }

  int _seriesCategoryCount(String category) {
    return _categoryCounts[category] ?? 0;
  }

  void _switchCategoryRelative(int delta) {
    if (_categories.isEmpty) return;
    int currentIndex = _categories.indexOf(_selectedCategory);
    if (currentIndex == -1) currentIndex = 0;

    int newIndex = (currentIndex + delta) % _categories.length;
    if (newIndex < 0) newIndex += _categories.length;

    unawaited(_selectSeriesCategory(_categories[newIndex]));
  }

  bool _isLockableSeriesCategory(String category) =>
      category != 'Tümü' &&
      category != 'Favoriler' &&
      category != _recentlyWatchedCategory &&
      category != _newlyAddedCategory;

  Future<void> _selectSeriesCategory(
    String category, {
    bool closeSidebar = false,
  }) async {
    if (!mounted) return;
    setState(() {
      _selectedCategory = category;
      _selectedSeriesIndex = 0;
      _filteredSeries = _computeFilteredSeries();
      if (closeSidebar) {
        _showCategoriesSidebar = false;
        _showProfilesSidebar = false;
        _remoteMode = _RemoteMode.sidebarSeries;
      }
    });
    _scrollToSelectedCategoryInSidebar();
    _scrollToSelectedCategory();
    _scrollToFocusedSeries();
    final filtered = _filteredSeries;
    if (filtered.isNotEmpty) {
      _loadMetadata(filtered[0].name, filtered[0].category);
    }
  }

  Future<void> _activateCurrentSeriesCategory() async {
    await _selectSeriesCategory(_selectedCategory, closeSidebar: true);
  }

  Future<void> _hideCurrentSeriesCategory() async {
    final category = _selectedCategory;
    if (!_isLockableSeriesCategory(category)) return;
    final hidden = await hideCategoryWithParentalControl(
      context,
      settings: _settings,
      type: 'series',
      category: categoryLabel(category),
      profileId: categoryProfileId(category) ?? _currentProfile.id,
    );
    if (!mounted || !hidden) return;
    _updateCategories(_series);
    await _selectSeriesCategory('Tümü');
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      if (_searchFocusNode.hasFocus) {
        FocusScope.of(context).requestFocus(_keyboardFocusNode);
        setState(() => _remoteMode = _RemoteMode.sidebarSearch);
      } else if (_showCategoriesSidebar || _showProfilesSidebar) {
        setState(() {
          _showCategoriesSidebar = false;
          _showProfilesSidebar = false;
          _remoteMode = _RemoteMode.sidebarSeries;
        });
      } else if (_remoteMode != _RemoteMode.topNav) {
        _openTopNav();
      }
      return;
    }

    if (key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.pageDown) {
      _switchCategoryRelative(1);
      return;
    }
    if (key == LogicalKeyboardKey.mediaRewind ||
        key == LogicalKeyboardKey.pageUp) {
      _switchCategoryRelative(-1);
      return;
    }

    if (_searchFocusNode.hasFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        FocusScope.of(context).requestFocus(_keyboardFocusNode);
        setState(() => _remoteMode = _RemoteMode.sidebarHeader);
        return;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        FocusScope.of(context).requestFocus(_keyboardFocusNode);
        setState(() => _remoteMode = _RemoteMode.sidebarSeries);
        return;
      }
      return; // Textfield takes over other keys
    }

    switch (_remoteMode) {
      case _RemoteMode.sidebarHeader:
        if (key == LogicalKeyboardKey.arrowDown) {
          setState(() => _remoteMode = _RemoteMode.sidebarSearch);
        } else if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _showSettings(context);
        } else if (key == LogicalKeyboardKey.arrowRight) {
          setState(() {
            _remoteMode = _RemoteMode.mainContent;
          });
        }
        break;
      case _RemoteMode.sidebarSearch:
        if (key == LogicalKeyboardKey.arrowUp) {
          setState(() => _remoteMode = _RemoteMode.sidebarHeader);
        } else if (key == LogicalKeyboardKey.arrowDown) {
          setState(() => _remoteMode = _RemoteMode.sidebarSeries);
        } else if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _searchFocusNode.requestFocus();
        } else if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape) {
          setState(() => _remoteMode = _RemoteMode.sidebarSeries);
        }
        break;
      case _RemoteMode.sidebarFooter:
        if (key == LogicalKeyboardKey.arrowUp) {
          setState(() => _remoteMode = _RemoteMode.sidebarSeries);
          _scrollToFocusedSeries();
        } else if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const UserSelectionScreen(),
            ),
          ).then((_) {
            if (mounted) {
              final provider = Provider.of<ChannelProvider>(
                context,
                listen: false,
              );
              _updateCategories(provider.uniqueSeries);
              setState(() {});
            }
          });
        } else if (key == LogicalKeyboardKey.arrowRight) {
          setState(() {
            _remoteMode = _RemoteMode.mainContent;
          });
        }
        break;
      case _RemoteMode.mainContent:
        if (key == LogicalKeyboardKey.arrowLeft) {
          setState(() => _remoteMode = _RemoteMode.sidebarSeries);
        } else if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _showEpisodesDialog(_filteredSeries[_selectedSeriesIndex]);
        }
        break;
      case _RemoteMode.sidebarSeries:
        if (key == LogicalKeyboardKey.arrowDown) {
          if (_selectedSeriesIndex < _filteredSeries.length - 1) {
            _changeSeries(_selectedSeriesIndex + 1);
            _scrollToFocusedSeries();
          } else {
            setState(() => _remoteMode = _RemoteMode.sidebarFooter);
          }
        } else if (key == LogicalKeyboardKey.arrowUp) {
          if (_selectedSeriesIndex > 0) {
            _changeSeries(_selectedSeriesIndex - 1);
            _scrollToFocusedSeries();
          } else {
            setState(() => _remoteMode = _RemoteMode.sidebarSearch);
            FocusScope.of(context).requestFocus(_keyboardFocusNode);
          }
        } else if (key == LogicalKeyboardKey.arrowRight) {
          setState(() {
            _remoteMode = _RemoteMode.mainContent;
          });
        } else if (key == LogicalKeyboardKey.arrowLeft) {
          setState(() {
            _showCategoriesSidebar = true;
            _showProfilesSidebar = false;
            _remoteMode = _RemoteMode.sidebarCategories;
          });
          _scrollToSelectedCategoryInSidebar();
        } else if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          if (_filteredSeries.isNotEmpty) {
            _showEpisodesDialog(_filteredSeries[_selectedSeriesIndex]);
          }
        }
        break;
      case _RemoteMode.sidebarCategories:
        if (key == LogicalKeyboardKey.arrowDown) {
          int idx = _categories.indexOf(_selectedCategory);
          if (idx < _categories.length - 1) {
            unawaited(_selectSeriesCategory(_categories[idx + 1]));
          }
        } else if (key == LogicalKeyboardKey.arrowUp) {
          int idx = _categories.indexOf(_selectedCategory);
          if (idx > 0) {
            unawaited(_selectSeriesCategory(_categories[idx - 1]));
          }
        } else if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          unawaited(_activateCurrentSeriesCategory());
        } else if (key == LogicalKeyboardKey.arrowLeft) {
          if (!_hasMultipleProfiles) break;
          final profiles = _profileFilters;
          setState(() {
            _showCategoriesSidebar = false;
            _showProfilesSidebar = true;
            _remoteMode = _RemoteMode.sidebarProfiles;
            _focusedProfileIndex = profiles.indexWhere(
              (profile) => profile?.id == _selectedProfileId,
            );
            if (_focusedProfileIndex < 0) _focusedProfileIndex = 0;
          });
          _scrollToProfileIndex(_focusedProfileIndex);
        }
        break;
      case _RemoteMode.sidebarProfiles:
        final profiles = _profileFilters;
        if (key == LogicalKeyboardKey.arrowDown) {
          setState(() {
            if (_focusedProfileIndex < profiles.length - 1) {
              _focusedProfileIndex++;
            }
          });
          _scrollToProfileIndex(_focusedProfileIndex);
        } else if (key == LogicalKeyboardKey.arrowUp) {
          setState(() {
            if (_focusedProfileIndex > 0) _focusedProfileIndex--;
          });
          _scrollToProfileIndex(_focusedProfileIndex);
        } else if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _activateFocusedProfile();
        }
        break;
      case _RemoteMode.topNav:
        if (key == LogicalKeyboardKey.arrowDown) {
          _topNavKey.currentState?.collapse();
        } else if (key == LogicalKeyboardKey.arrowLeft) {
          final dur =
              _settings.autoHideDuration > 0 ? _settings.autoHideDuration : 3.0;
          _topNavKey.currentState?.navigateLeft(dur);
        } else if (key == LogicalKeyboardKey.arrowRight) {
          final dur =
              _settings.autoHideDuration > 0 ? _settings.autoHideDuration : 3.0;
          _topNavKey.currentState?.navigateRight(dur);
        } else if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _topNavKey.currentState?.selectCurrent(context);
        }
        break;
    }
  }

  void _openTopNav() {
    _topNavOpenedAt = DateTime.now();
    setState(() => _remoteMode = _RemoteMode.topNav);
    final dur =
        _settings.autoHideDuration > 0 ? _settings.autoHideDuration : 3.0;
    _topNavKey.currentState?.expandForRemote(dur);
  }

  void _scrollToFocusedSeries() {
    if (!mounted || !_sidebarScrollController.hasClients) return;
    final double vh = _sidebarScrollController.position.viewportDimension;
    if (vh <= 0) return;
    final double maxScroll = _sidebarScrollController.position.maxScrollExtent;
    final double target = (_selectedSeriesIndex * _sidebarItemExtent) -
        (vh / 2) +
        (_sidebarItemExtent / 2);
    _sidebarScrollController.jumpTo(target.clamp(0.0, maxScroll));
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<WatchHistoryProvider>(context);
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (_favoriteLongPress.handle(
          event,
          enabled: _remoteMode == _RemoteMode.sidebarSeries &&
              _filteredSeries.isNotEmpty,
          onShortPress: () =>
              _showEpisodesDialog(_filteredSeries[_selectedSeriesIndex]),
          onLongPress: _toggleSelectedSeriesFavorite,
        )) {
          return KeyEventResult.handled;
        }
        if (_categoryLongPress.handle(
          event,
          enabled: _remoteMode == _RemoteMode.sidebarCategories,
          onShortPress: () => unawaited(_activateCurrentSeriesCategory()),
          onLongPress: () {
            _categoryLongPress.cancel();
            unawaited(_hideCurrentSeriesCategory());
          },
        )) {
          return KeyEventResult.handled;
        }
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape) {
          final now = DateTime.now();
          if (_lastModalClosedAt != null &&
              now.difference(_lastModalClosedAt!) <
                  const Duration(milliseconds: 300)) {
            return KeyEventResult.handled;
          }

          if (_remoteMode == _RemoteMode.topNav) {
            if (_topNavOpenedAt != null &&
                now.difference(_topNavOpenedAt!) <
                    const Duration(milliseconds: 300)) {
              return KeyEventResult.handled;
            }
            SystemNavigator.pop();
            return KeyEventResult.handled;
          } else {
            _handleKeyEvent(event);
            return KeyEventResult.handled;
          }
        }

        _handleKeyEvent(event);
        if (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              final now = DateTime.now();
              if (_lastModalClosedAt != null &&
                  now.difference(_lastModalClosedAt!) <
                      const Duration(milliseconds: 300)) {
                return;
              }
              if (_remoteMode == _RemoteMode.topNav) {
                if (_topNavOpenedAt != null &&
                    now.difference(_topNavOpenedAt!) <
                        const Duration(milliseconds: 300)) {
                  return;
                }
                SystemNavigator.pop();
              } else {
                _openTopNav();
              }
            },
            child: Scaffold(
              backgroundColor: AppColors.backgroundDark,
              body: Stack(
                children: [
                  Positioned(
                    left: _sidebarWidth,
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildMainContent(),
                  ),
                  _buildLeftSidebar(),
                  SafeArea(
                    child: TopNavBar(
                      key: _topNavKey,
                      activeScreen: 'series',
                      onDismiss: () {
                        if (mounted && _remoteMode == _RemoteMode.topNav) {
                          setState(
                            () => _remoteMode = _RemoteMode.sidebarSeries,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainContent() {
    final filtered = _filteredSeries;
    if (filtered.isEmpty) {
      return Column(
        children: [
          _buildRightHeader(),
          Expanded(
            child: Center(
              child: Text(
                _settings.getText('no_content_found'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    if (_selectedSeriesIndex >= filtered.length) {
      _selectedSeriesIndex = 0;
    }
    final heroSeries = filtered[_selectedSeriesIndex];
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: 0.6,
            child: ShaderMask(
              shaderCallback: (rect) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.transparent],
                  stops: [0.5, 1.0],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstIn,
              child: Image.network(
                heroSeries.logoUrl ??
                    'https://images.unsplash.com/photo-1626814026160-2237a95fc5a0?q=80&w=2070&auto=format&fit=crop',
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: Colors.black),
              ),
            ),
          ),
        ),
        Column(
          children: [
            _buildRightHeader(),
            Expanded(
              child: Stack(
                children: [
                  Positioned(
                    left: 24,
                    bottom: 24,
                    child: _buildHeroContent(heroSeries),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLeftSidebar() {
    final filtered = _filteredSeries;
    return Container(
      width: _sidebarWidth,
      decoration: BoxDecoration(
        color: const Color(
          0xFF131022,
        ).withValues(alpha: _settings.sidebarOpacity),
        border: const Border(right: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSidebarHeader(),
          _buildSearchBar(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Divider(color: Colors.white10, height: 1),
          ),
          Expanded(
            child: Stack(
              children: [
                Opacity(
                  opacity:
                      _showCategoriesSidebar || _showProfilesSidebar ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: _showCategoriesSidebar || _showProfilesSidebar,
                    child: _buildSeriesList(filtered),
                  ),
                ),
                if (_showCategoriesSidebar) _buildCategoriesPanel(),
                if (_showProfilesSidebar) _buildProfilesPanel(),
              ],
            ),
          ),
          _buildSidebarFooter(),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (Navigator.canPop(context)) ...[
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 10),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'TIVUQ',
                          style: GoogleFonts.splineSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: 'IPTV',
                          style: GoogleFonts.splineSans(
                            fontWeight: FontWeight.bold,
                            color: _settings.primaryColor,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _settings.getText('series'),
                    style: GoogleFonts.notoSans(
                      fontSize: 8,
                      color: Colors.grey,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          InkWell(
            onTap: () => _showSettings(context),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: Duration.zero,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _remoteMode == _RemoteMode.sidebarHeader
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _remoteMode == _RemoteMode.sidebarHeader
                      ? Colors.white
                      : Colors.transparent,
                  width: _remoteMode == _RemoteMode.sidebarHeader ? 2 : 1,
                ),
              ),
              child: const Icon(Icons.settings, color: Colors.grey, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 36),
            onPressed: () {
              setState(() {
                _showCategoriesSidebar = !_showCategoriesSidebar;
                _showProfilesSidebar = false;
                _remoteMode = _showCategoriesSidebar
                    ? _RemoteMode.sidebarCategories
                    : _RemoteMode.sidebarSeries;
              });
              if (_showCategoriesSidebar) {
                _scrollToSelectedCategoryInSidebar();
              }
            },
            icon: Icon(
              _showCategoriesSidebar ? Icons.menu_open : Icons.menu,
              color: _showCategoriesSidebar
                  ? _settings.primaryColor
                  : Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  color: _remoteMode == _RemoteMode.sidebarSearch
                      ? Colors.white
                      : Colors.white10,
                  width: _remoteMode == _RemoteMode.sidebarSearch ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, color: Colors.grey, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      focusNode: _searchFocusNode,
                      onChanged: (v) {
                        setState(() {
                          _searchQuery = v;
                          _selectedSeriesIndex = 0;
                          _filteredSeries = _computeFilteredSeries();
                        });
                        final filtered = _filteredSeries;
                        if (filtered.isNotEmpty) {
                          _loadMetadata(filtered[0].name, filtered[0].category);
                        }
                      },
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: _settings.getText('search_series'),
                        hintStyle: GoogleFonts.notoSans(
                          color: Colors.grey[500],
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesList(List<Channel> filtered) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 6, 16, 4),
          child: Text(
            _settings.getText('series_list').toUpperCase(),
            style: GoogleFonts.notoSans(
              color: Colors.grey,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _sidebarScrollController,
            itemExtent: _sidebarItemExtent,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final series = filtered[index];
              final isSelected = _selectedSeriesIndex == index;
              return _buildSeriesItem(series, index, isSelected);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSeriesItem(Channel series, int index, bool isSelected) {
    final isFocused = isSelected && _remoteMode == _RemoteMode.sidebarSeries;
    final isFavorite = _settings.isFavorite(
      'series',
      series.id,
      profileId: series.sourceProfileId,
    );
    final history =
        Provider.of<WatchHistoryProvider>(context, listen: true).getProgress(
      _seriesHistoryId(series),
      profileId: series.sourceProfileId ?? _currentProfile.id,
    );
    final progress = history?.percent ?? 0.0;
    return InkWell(
      onTap: () => _changeSeries(index),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: Duration.zero,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? _settings.primaryColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFocused
                ? Colors.white
                : (isSelected
                    ? _settings.primaryColor.withValues(alpha: 0.4)
                    : Colors.transparent),
            width: isFocused ? 2 : 1,
          ),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.name,
                    style: GoogleFonts.notoSans(
                      color: isSelected ? Colors.white : Colors.grey[300],
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (progress > 0) ...[
                    const SizedBox(height: 3),
                    _buildWatchProgress(progress),
                  ],
                ],
              ),
            ),
            if (isFavorite) ...[
              const SizedBox(width: 6),
              Icon(Icons.favorite, color: _settings.primaryColor, size: 15),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWatchProgress(double progress) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: _settings.primaryColor.withValues(alpha: 0.2),
          valueColor: AlwaysStoppedAnimation<Color>(_settings.primaryColor),
        ),
      ),
    );
  }

  Widget _buildCategoriesPanel() {
    return Container(
      color: const Color(
        0xFF161325,
      ).withValues(alpha: _settings.sidebarOpacity),
      child: ListView.builder(
        controller: _categorySidebarScrollController,
        itemExtent: _categoryItemExtent,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == _selectedCategory;

          if (!_categorySidebarKeys.containsKey(cat)) {
            _categorySidebarKeys[cat] = GlobalKey();
          }

          return InkWell(
            key: _categorySidebarKeys[cat],
            onTap: () =>
                unawaited(_selectSeriesCategory(cat, closeSidebar: true)),
            child: AnimatedContainer(
              duration: Duration.zero,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? _settings.primaryColor.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      isSelected && _remoteMode == _RemoteMode.sidebarCategories
                          ? Colors.white
                          : (isSelected
                              ? _settings.primaryColor.withValues(alpha: 0.3)
                              : Colors.transparent),
                  width:
                      isSelected && _remoteMode == _RemoteMode.sidebarCategories
                          ? 2
                          : 1,
                ),
              ),
              child: Row(
                children: [
                  if (isSelected)
                    Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _settings.primaryColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  if (isSelected) const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${categoryProfileId(cat) == null ? _settings.getText(_getCategoryKey(cat)) : categoryLabel(cat)} '
                      '(${_seriesCategoryCount(cat)})',
                      style: GoogleFonts.notoSans(
                        color: isSelected ? Colors.white : Colors.grey[400],
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      color: _settings.primaryColor,
                      size: 16,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfilesPanel() {
    final profiles = _profileFilters;
    return Container(
      color: const Color(
        0xFF12101F,
      ).withValues(alpha: _settings.sidebarOpacity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Text(
              _settings.getText('user_selection').toUpperCase(),
              style: GoogleFonts.notoSans(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _profileSidebarScrollController,
              itemExtent: _categoryItemExtent,
              itemCount: profiles.length,
              itemBuilder: (context, index) {
                final profile = profiles[index];
                final profileId = profile?.id;
                final isSelected = profileId == _selectedProfileId;
                final isFocused = _focusedProfileIndex == index;
                final title = profile?.name ?? _settings.getText('all');
                return InkWell(
                  canRequestFocus: false,
                  onTap: () {
                    setState(() => _focusedProfileIndex = index);
                    _activateFocusedProfile();
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _settings.primaryColor.withValues(alpha: 0.15)
                          : (isFocused
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.transparent),
                      borderRadius: BorderRadius.circular(12),
                      border: isFocused
                          ? Border.all(color: Colors.white, width: 2)
                          : (isSelected
                              ? Border.all(
                                  color: _settings.primaryColor.withValues(
                                    alpha: 0.3,
                                  ),
                                )
                              : null),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: isSelected || isFocused
                              ? _settings.primaryColor
                              : Colors.white12,
                          child: profile == null
                              ? const Icon(
                                  Icons.people_alt_rounded,
                                  color: Colors.white,
                                  size: 15,
                                )
                              : Text(
                                  profile.initial,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            '$title (${_profileSeriesCount(profileId)})',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSans(
                              color: isSelected || isFocused
                                  ? Colors.white
                                  : Colors.grey[400],
                              fontSize: 13,
                              fontWeight: isSelected || isFocused
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: _settings.primaryColor,
                            size: 16,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarFooter() {
    Profile sourceProfile = _currentProfile;
    String? sourceId =
        _selectedProfileId ?? categoryProfileId(_selectedCategory);
    if (sourceId == null && _filteredSeries.isNotEmpty) {
      final index = _selectedSeriesIndex.clamp(0, _filteredSeries.length - 1);
      sourceId = _filteredSeries[index].sourceProfileId;
    }
    if (sourceId != null) {
      try {
        sourceProfile = _settings.profiles.firstWhere((p) => p.id == sourceId);
      } catch (_) {}
    }
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const UserSelectionScreen()),
        ).then((_) {
          if (mounted) {
            final provider = Provider.of<ChannelProvider>(
              context,
              listen: false,
            );
            _updateCategories(provider.uniqueSeries);
            setState(() {});
          }
        });
      },
      child: AnimatedContainer(
        duration: Duration.zero,
        padding: const EdgeInsets.fromLTRB(24, 8, 8, 16),
        decoration: BoxDecoration(
          color: _remoteMode == _RemoteMode.sidebarFooter
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
          border: const Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: _settings.primaryColor,
              child: Text(
                sourceProfile.initial,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              sourceProfile.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(48, 8, 48, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0B).withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _categoryScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((cat) {
                  final isSelected = cat == _selectedCategory;
                  if (!_categoryKeys.containsKey(cat)) {
                    _categoryKeys[cat] = GlobalKey();
                  }
                  return Padding(
                    key: _categoryKeys[cat],
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () => unawaited(_selectSeriesCategory(cat)),
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: Duration.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _settings.primaryColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (cat == 'Favoriler') ...[
                              Icon(
                                isSelected
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[400],
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              categoryProfileId(cat) == null
                                  ? _settings.getText(_getCategoryKey(cat))
                                  : categoryLabel(cat),
                              style: GoogleFonts.notoSans(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[400],
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroContent(Channel series) {
    final cleanName = MetadataService.cleanTitle(series.name);
    final title = _currentMetadata?.title ?? cleanName;
    final year = _currentMetadata?.year ?? '';
    final genre = _currentMetadata?.genre ?? categoryLabel(series.category);
    final rating = _currentMetadata?.rating ?? '';
    final desc = _currentMetadata?.description ?? '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Genre
            Text(
              genre.toUpperCase(),
              style: GoogleFonts.notoSans(
                color: _settings.primaryColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 6),

            // Title
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.splineSans(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.4,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 10),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isLoadingMetadata
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 80,
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (year.isNotEmpty) ...[
                              _buildMetaBadge(year),
                              _buildDotSeparator(),
                            ],
                            if (rating.isNotEmpty) _buildMetaBadge(rating),
                          ],
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSans(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 12),

            _buildButton(
              _settings.getText('episodes'),
              Icons.list_rounded,
              isFocused: _remoteMode == _RemoteMode.mainContent,
              onTap: () => _showEpisodesDialog(series),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Text(
        text,
        style: GoogleFonts.notoSans(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDotSeparator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      width: 4,
      height: 4,
      decoration: const BoxDecoration(
        color: Colors.white38,
        shape: BoxShape.circle,
      ),
    );
  }

  void _showEpisodesDialog(Channel series) {
    final provider = Provider.of<ChannelProvider>(context, listen: false);
    final episodesFuture = provider.loadSeriesEpisodes(series);

    showInstantDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) => FutureBuilder<List<Channel>>(
        future: episodesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Dialog(
              backgroundColor: const Color(0xFF131022),
              child: SizedBox(
                width: 320,
                height: 160,
                child: Center(
                  child: CircularProgressIndicator(
                    color: _settings.primaryColor,
                  ),
                ),
              ),
            );
          }
          final episodes = snapshot.data ?? const <Channel>[];
          if (episodes.isEmpty) {
            return Dialog(
              backgroundColor: const Color(0xFF131022),
              child: SizedBox(
                width: 420,
                height: 180,
                child: Center(
                  child: Text(
                    _settings.getText('no_content_found'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            );
          }
          return SeriesEpisodesDialog(
            seriesName: series.name,
            historyGroupId: _seriesHistoryId(series),
            episodes: episodes,
            closeText: _settings.getText('close'),
            primaryColor: _settings.primaryColor,
            profileId: series.sourceProfileId ?? _currentProfile.id,
          );
        },
      ),
    ).then((_) {
      if (mounted) {
        _lastModalClosedAt = DateTime.now();
        _updateCategories(_series);
        FocusScope.of(context).requestFocus(_keyboardFocusNode);
      }
    });
  }

  Widget _buildButton(
    String text,
    IconData icon, {
    bool isPrimary = false,
    bool isFocused = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: Duration.zero,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isPrimary
              ? _settings.primaryColor
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFocused ? Colors.white : Colors.transparent,
            width: 2,
          ),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: _settings.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showInstantDialog(
      context: context,
      builder: (context) =>
          SettingsOverlay(profile: widget.profile, vodPlaybackSettings: true),
    ).then((_) {
      _lastModalClosedAt = DateTime.now();
      if (mounted) _updateCategories(_series);
    });
  }
}
