import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/channel.dart';
import '../screens/video_player_screen.dart';
import '../providers/watch_history_provider.dart';
import 'package:provider/provider.dart';

class SeriesEpisodesDialog extends StatefulWidget {
  final String seriesName;
  final String historyGroupId;
  final List<Channel> episodes;
  final String closeText;
  final Color primaryColor;
  final String profileId;

  const SeriesEpisodesDialog({
    super.key,
    required this.seriesName,
    required this.historyGroupId,
    required this.episodes,
    required this.closeText,
    required this.primaryColor,
    required this.profileId,
  });

  @override
  State<SeriesEpisodesDialog> createState() => _SeriesEpisodesDialogState();
}

class _SeriesEpisodesDialogState extends State<SeriesEpisodesDialog> {
  final Map<String, List<Channel>> _seasons = {};
  late List<String> _seasonNames;

  int _selectedSeasonIndex = 0;
  int _selectedEpisodeIndex = 0;
  int _focusedColumn = 0; // 0: Seasons, 1: Episodes

  final ScrollController _seasonScrollController = ScrollController();
  final ScrollController _episodeScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _parseSeasons();
  }

  @override
  void dispose() {
    _seasonScrollController.dispose();
    _episodeScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _parseSeasons() {
    final seasonRegExp = RegExp(
      r'(?:S|Season|Sezon)\s*0*(\d+)',
      caseSensitive: false,
    );

    for (var ep in widget.episodes) {
      final match = seasonRegExp.firstMatch(ep.name);
      String seasonName = '1. Sezon';

      if (match != null && match.groupCount >= 1) {
        seasonName = '${match.group(1)}. Sezon';
      }

      if (!_seasons.containsKey(seasonName)) {
        _seasons[seasonName] = [];
      }
      _seasons[seasonName]!.add(ep);
    }

    // Sort season names numerically if possible
    _seasonNames = _seasons.keys.toList()
      ..sort((a, b) {
        final numA = int.tryParse(a.split('.').first) ?? 0;
        final numB = int.tryParse(b.split('.').first) ?? 0;
        return numA.compareTo(numB);
      });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      if (_focusedColumn == 0) {
        // Seasons Column
        if (key == LogicalKeyboardKey.arrowDown) {
          if (_selectedSeasonIndex < _seasonNames.length - 1) {
            _selectedSeasonIndex++;
            _selectedEpisodeIndex = 0;
            _scrollToSeason();
            _scrollToEpisode();
          }
        } else if (key == LogicalKeyboardKey.arrowUp) {
          if (_selectedSeasonIndex > 0) {
            _selectedSeasonIndex--;
            _selectedEpisodeIndex = 0;
            _scrollToSeason();
            _scrollToEpisode();
          }
        } else if (key == LogicalKeyboardKey.arrowRight) {
          _focusedColumn = 1;
        } else if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _focusedColumn = 1;
        }
      } else if (_focusedColumn == 1) {
        // Episodes Column
        final currentSeasonEpisodes =
            _seasons[_seasonNames[_selectedSeasonIndex]]!;

        if (key == LogicalKeyboardKey.arrowDown) {
          if (_selectedEpisodeIndex < currentSeasonEpisodes.length - 1) {
            _selectedEpisodeIndex++;
            _scrollToEpisode();
          }
        } else if (key == LogicalKeyboardKey.arrowUp) {
          if (_selectedEpisodeIndex > 0) {
            _selectedEpisodeIndex--;
            _scrollToEpisode();
          }
        } else if (key == LogicalKeyboardKey.arrowLeft) {
          _focusedColumn = 0;
        } else if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _playEpisode(_selectedEpisodeIndex);
        }
      }
    });
  }

  void _scrollToSeason() {
    if (!_seasonScrollController.hasClients) return;
    const double itemH = 50.0;
    final double vh = _seasonScrollController.position.viewportDimension;
    final double target =
        (_selectedSeasonIndex * itemH) - (vh / 2) + (itemH / 2);
    _seasonScrollController.jumpTo(
      target.clamp(0.0, _seasonScrollController.position.maxScrollExtent),
    );
  }

  void _scrollToEpisode() {
    if (!_episodeScrollController.hasClients) return;
    const double itemH = 60.0;
    final double vh = _episodeScrollController.position.viewportDimension;
    final double target =
        (_selectedEpisodeIndex * itemH) - (vh / 2) + (itemH / 2);
    _episodeScrollController.jumpTo(
      target.clamp(0.0, _episodeScrollController.position.maxScrollExtent),
    );
  }

  void _playEpisode(int index) {
    final episodes = _seasons[_seasonNames[_selectedSeasonIndex]]!;
    final ep = episodes[index];
    final allEpisodes = <Channel>[
      for (final seasonName in _seasonNames) ..._seasons[seasonName]!,
    ];
    final globalIndex = allEpisodes.indexWhere((item) => item.url == ep.url);
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          url: ep.url,
          title: ep.name,
          profileId: widget.profileId,
          httpHeaders: ep.httpHeaders,
          playlist: episodes,
          initialIndex: index,
          historyGroupId: widget.historyGroupId,
          historyGroupItemCount: allEpisodes.length,
          historyGroupIndexOffset:
              (globalIndex < 0 ? index : globalIndex) - index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final historyProvider = Provider.of<WatchHistoryProvider>(
      context,
      listen: true,
    );

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        final key = event.logicalKey;
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
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 800,
          height: 500,
          decoration: BoxDecoration(
            color: const Color(0xFF131022),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.seriesName,
                      style: GoogleFonts.splineSans(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: Row(
                  children: [
                    // Seasons List
                    Container(
                      width: 250,
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: Colors.white10),
                        ),
                      ),
                      child: ListView.builder(
                        controller: _seasonScrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _seasonNames.length,
                        itemBuilder: (context, index) {
                          final season = _seasonNames[index];
                          final isSelected = _selectedSeasonIndex == index;
                          final isFocused = isSelected && _focusedColumn == 0;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedSeasonIndex = index;
                                _selectedEpisodeIndex = 0;
                                _focusedColumn = 1;
                              });
                            },
                            child: AnimatedContainer(
                              duration: Duration.zero,
                              height: 50,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? widget.primaryColor.withValues(
                                        alpha: isFocused ? 1.0 : 0.2,
                                      )
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isFocused
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: isFocused ? 2 : 1,
                                ),
                              ),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                season,
                                style: TextStyle(
                                  color: isSelected && isFocused
                                      ? Colors.white
                                      : (isSelected
                                          ? widget.primaryColor
                                          : Colors.white70),
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Episodes List
                    Expanded(
                      child: ListView.builder(
                        controller: _episodeScrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _seasons[_seasonNames[_selectedSeasonIndex]]!
                            .length,
                        itemBuilder: (context, index) {
                          final ep = _seasons[
                              _seasonNames[_selectedSeasonIndex]]![index];
                          final isSelected = _selectedEpisodeIndex == index;
                          final isFocused = isSelected && _focusedColumn == 1;
                          final history = historyProvider.getProgress(
                            ep.url,
                            profileId: widget.profileId,
                          );

                          return InkWell(
                            onTap: () => _playEpisode(index),
                            child: AnimatedContainer(
                              duration: Duration.zero,
                              height: 60,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: isFocused
                                    ? widget.primaryColor.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isFocused
                                      ? widget.primaryColor
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.play_circle_outline,
                                        color: isFocused
                                            ? widget.primaryColor
                                            : Colors.white54,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          ep.name,
                                          style: GoogleFonts.notoSans(
                                            color: isFocused
                                                ? Colors.white
                                                : Colors.white70,
                                            fontWeight: isFocused
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (history != null && history.percent > 0)
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: LinearProgressIndicator(
                                        value: history.percent,
                                        backgroundColor: Colors.transparent,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          widget.primaryColor.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                        minHeight: 2,
                                      ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
