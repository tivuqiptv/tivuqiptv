import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MovieMetadata {
  final String title;
  final String? year;
  final String? duration;
  final String? description;
  final String? genre;
  final String? director;
  final String? cast;
  final String? rating;

  MovieMetadata({
    required this.title,
    this.year,
    this.duration,
    this.description,
    this.genre,
    this.director,
    this.cast,
    this.rating,
  });
}

class MetadataService {
  static String cleanTitle(String originalTitle) {
    String title = originalTitle;

    // Remove country prefixes (e.g. TR:, ENG:, DE:, FR:, TR : etc.)
    title = title.replaceAll(
        RegExp(r'^[A-Z]{2,3}\s*:\s*', caseSensitive: false), '');
    title = title.replaceAll(
        RegExp(r'^[A-Z]{2,3}\s*-\s*', caseSensitive: false), '');

    // Remove quality and resolution tags
    title = title.replaceAll(
        RegExp(
            r'\b(1080p|720p|4k|uhd|x264|x265|h264|bluray|dual|webrip|web-dl|dvdrip|hevc|3d|rip|1080|720)\b',
            caseSensitive: false),
        '');

    // Remove common bracket indicators
    title = title.replaceAll(RegExp(r'\[.*?\]'), '');
    title = title.replaceAll(RegExp(r'\(.*?\)'), '');

    // Remove years from title (e.g. 2018, 2020)
    title = title.replaceAll(RegExp(r'\b(19\d{2}|20\d{2})\b'), '');

    // Strip other unwanted chars
    title = title.replaceAll(RegExp(r'[-–|]+'), ' ');

    // Remove multiple spaces
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    return title.isNotEmpty ? title : originalTitle;
  }

  static Future<MovieMetadata> fetchMetadata(
      String originalTitle, String category) async {
    final String cleaned = cleanTitle(originalTitle);

    // Parse year from original title as fallback
    final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(originalTitle);
    String? fallbackYear = yearMatch?.group(1);
    if (fallbackYear == null) {
      final yearMatch2 =
          RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(originalTitle);
      fallbackYear = yearMatch2?.group(1);
    }

    try {
      final isSeries = RegExp(
        r'dizi|series|season|sezon',
        caseSensitive: false,
      ).hasMatch(category);
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': cleaned,
        'media': isSeries ? 'tvShow' : 'movie',
        'entity': isSeries ? 'tvSeason' : 'movie',
        'limit': '3',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List results = data['results'] ?? [];
        if (results.isNotEmpty) {
          final item = results.firstWhere(
            (candidate) {
              final candidateTitle =
                  (candidate['trackName'] ?? candidate['collectionName'] ?? '')
                      .toString()
                      .toLowerCase();
              final wanted = cleaned.toLowerCase();
              return candidateTitle.contains(wanted) ||
                  wanted.contains(candidateTitle);
            },
            orElse: () => results.first,
          );

          final int? durationMillis = item['trackTimeMillis'];
          String? durationStr;
          if (durationMillis != null) {
            final duration = Duration(milliseconds: durationMillis);
            final hours = duration.inHours;
            final mins = duration.inMinutes.remainder(60);
            durationStr = hours > 0 ? '$hours sa $mins dk' : '$mins dk';
          }

          final String? releaseDate = item['releaseDate'];
          String? year = fallbackYear;
          if (releaseDate != null && releaseDate.length >= 4) {
            year = releaseDate.substring(0, 4);
          }

          return MovieMetadata(
            title: cleaned,
            year: year,
            duration: durationStr,
            description: item['longDescription'] ?? item['shortDescription'],
            genre: item['primaryGenreName'] ?? category,
            director: item['artistName'],
            rating: item['contentAdvisoryRating'],
          );
        }
      }
    } catch (e) {
      debugPrint('Metadata fetch error: $e');
    }

    // Sonuç yoksa tahminî yıl, süre veya yaş derecesi üretme.
    return MovieMetadata(
      title: cleaned,
      year: fallbackYear,
      genre: category,
    );
  }
}
