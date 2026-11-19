import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/current_app_localizations.dart';
import '../../../../util/playback_time_label.dart';

const bookDiscoverPageSize = 24;

const bookDiscoverSubjectsPrefKey = 'book_discover_subjects';
const bookDiscoverAudiobookGenresPrefKey = 'book_discover_audiobook_genres';

const bookDiscoverAccent = Color(0xFF32B9E8);

const bookDiscoverGenrePool = <String>[
  'architecture',
  'art__art_instruction',
  'history_of_art__art__design_styles',
  'dance',
  'design',
  'fashion',
  'film',
  'graphic_design',
  'music',
  'music_theory',
  'painting__paintings',
  'photography',
  'bears',
  'cats',
  'kittens',
  'dogs',
  'puppies',
  'fiction',
  'romance',
  'fantasy',
  'mystery_and_detective_stories',
  'magic',
  'literature',
  'plays',
  'short_stories',
  'young_adult_fiction',
  'sciencemathematics',
  'biology',
  'chemistry',
  'mathematics',
  'physics',
  'programming',
  'business',
  'management',
  'entrepreneurship',
  'business__economics',
  'success_in_business',
  'finance',
  'mystery',
  'science_fiction',
  'juvenile_fiction',
  'juvenile_literature',
  'stories_in_rhyme',
  'infancy',
  'bedtime',
  'picture_books',
  'history',
  'ancient_civilization',
  'archaeology',
  'anthropology',
  'cooking',
  'cookbooks',
  'mental_health',
  'exercise',
  'nutrition',
  'self-help',
  'biography',
  'autobiography',
  'religion',
  'political_science',
  'psychology',
  'place%3Abrazil',
  'place%3Aindia',
  'place%3Aindonesia',
  'place%3Aunited_states',
  'textbooks',
  'historical_fiction',
  'thriller',
  'horror',
  'poetry',
];

const librivoxGenrePool = <String>[
  'Action & Adventure',
  'Adventure Fiction',
  'Biography & Autobiography',
  "Children's Fiction",
  'Classical',
  'Detective Fiction',
  'Drama',
  'Fantasy Fiction',
  'General Fiction',
  'General Non-fiction',
  'Historical Fiction',
  'Horror & Supernatural Fiction',
  'Humor',
  'Humorous Fiction',
  'Mystery & Detective Stories',
  'Mythology',
  'Nature',
  'Naval Fiction',
  'Philosophy',
  'Plays',
  'Poetry',
  'Religion',
  'Romance',
  'Satire',
  'Science Fiction',
  'Short Stories',
  'Travel & Geography',
  'Tragedy',
  'War & Military Fiction',
  'Westerns',
];

const audiobookPlaceholderColors = <Color>[
  Color(0xFF1A5C9A),
  Color(0xFF2E7D32),
  Color(0xFF6A1B9A),
  Color(0xFF00695C),
  Color(0xFFC62828),
  Color(0xFF4527A0),
  Color(0xFF558B2F),
  Color(0xFF283593),
  Color(0xFF4E342E),
  Color(0xFF00838F),
];

/// Kos TV: an Open Library subject's or a LibriVox genre's label in the
/// app's language. Both services still get the English slug or genre; null
/// for one with no label (a subject saved by an older build).
String? bookGenreLabel(AppLocalizations l10n, String subject) =>
    switch (subject) {
      'architecture' => l10n.kostvBookGenreArchitecture,
      'art__art_instruction' => l10n.kostvBookGenreArtInstruction,
      'history_of_art__art__design_styles' => l10n.kostvBookGenreArtHistory,
      'dance' => l10n.kostvBookGenreDance,
      'design' => l10n.kostvBookGenreDesign,
      'fashion' => l10n.kostvBookGenreFashion,
      'film' => l10n.kostvBookGenreFilm,
      'graphic_design' => l10n.kostvBookGenreGraphicDesign,
      'music' => l10n.kostvBookGenreMusic,
      'music_theory' => l10n.kostvBookGenreMusicTheory,
      'painting__paintings' => l10n.kostvBookGenrePainting,
      'photography' => l10n.kostvBookGenrePhotography,
      'bears' => l10n.kostvBookGenreBears,
      'cats' => l10n.kostvBookGenreCats,
      'kittens' => l10n.kostvBookGenreKittens,
      'dogs' => l10n.kostvBookGenreDogs,
      'puppies' => l10n.kostvBookGenrePuppies,
      'fiction' => l10n.kostvBookGenreFiction,
      'romance' => l10n.kostvBookGenreRomance,
      'fantasy' => l10n.kostvBookGenreFantasy,
      'mystery_and_detective_stories' => l10n.kostvBookGenreMysteryAndDetectiveStories,
      'magic' => l10n.kostvBookGenreMagic,
      'literature' => l10n.kostvBookGenreLiterature,
      'plays' => l10n.kostvBookGenrePlays,
      'short_stories' => l10n.kostvBookGenreShortStories,
      'young_adult_fiction' => l10n.kostvBookGenreYoungAdult,
      'sciencemathematics' => l10n.kostvBookGenreScienceMathematics,
      'biology' => l10n.kostvBookGenreBiology,
      'chemistry' => l10n.kostvBookGenreChemistry,
      'mathematics' => l10n.kostvBookGenreMathematics,
      'physics' => l10n.kostvBookGenrePhysics,
      'programming' => l10n.kostvBookGenreProgramming,
      'business' => l10n.kostvBookGenreBusiness,
      'management' => l10n.kostvBookGenreManagement,
      'entrepreneurship' => l10n.kostvBookGenreEntrepreneurship,
      'business__economics' => l10n.kostvBookGenreBusinessEconomics,
      'success_in_business' => l10n.kostvBookGenreBusinessSuccess,
      'finance' => l10n.kostvBookGenreFinance,
      'mystery' => l10n.kostvBookGenreMystery,
      'science_fiction' => l10n.kostvBookGenreScienceFiction,
      'juvenile_fiction' => l10n.kostvBookGenreChildrens,
      'juvenile_literature' => l10n.kostvBookGenreKidsBooks,
      'stories_in_rhyme' => l10n.kostvBookGenreStoriesInRhyme,
      'infancy' => l10n.kostvBookGenreInfancy,
      'bedtime' => l10n.kostvBookGenreBedtime,
      'picture_books' => l10n.kostvBookGenrePictureBooks,
      'history' => l10n.kostvBookGenreHistory,
      'ancient_civilization' => l10n.kostvBookGenreAncientCivilization,
      'archaeology' => l10n.kostvBookGenreArchaeology,
      'anthropology' => l10n.kostvBookGenreAnthropology,
      'cooking' => l10n.kostvBookGenreCooking,
      'cookbooks' => l10n.kostvBookGenreCookbooks,
      'mental_health' => l10n.kostvBookGenreMentalHealth,
      'exercise' => l10n.kostvBookGenreExercise,
      'nutrition' => l10n.kostvBookGenreNutrition,
      'self-help' => l10n.kostvBookGenreSelfHelp,
      'biography' => l10n.kostvBookGenreBiography,
      'autobiography' => l10n.kostvBookGenreAutobiography,
      'religion' => l10n.kostvBookGenreReligion,
      'political_science' => l10n.kostvBookGenrePoliticalScience,
      'psychology' => l10n.kostvBookGenrePsychology,
      'place%3Abrazil' => l10n.kostvBookGenreBrazil,
      'place%3Aindia' => l10n.kostvBookGenreIndia,
      'place%3Aindonesia' => l10n.kostvBookGenreIndonesia,
      'place%3Aunited_states' => l10n.kostvBookGenreUnitedStates,
      'textbooks' => l10n.kostvBookGenreTextbooks,
      'historical_fiction' => l10n.kostvBookGenreHistoricalFiction,
      'thriller' => l10n.kostvBookGenreThriller,
      'horror' => l10n.kostvBookGenreHorror,
      'poetry' => l10n.kostvBookGenrePoetry,
      'Action & Adventure' => l10n.kostvBookGenreActionAdventure,
      'Adventure Fiction' => l10n.kostvBookGenreAdventureFiction,
      'Biography & Autobiography' => l10n.kostvBookGenreBiographyAutobiography,
      'Children\'s Fiction' => l10n.kostvBookGenreChildrensFiction,
      'Classical' => l10n.kostvBookGenreClassical,
      'Detective Fiction' => l10n.kostvBookGenreDetectiveFiction,
      'Drama' => l10n.kostvBookGenreDrama,
      'Fantasy Fiction' => l10n.kostvBookGenreFantasyFiction,
      'General Fiction' => l10n.kostvBookGenreGeneralFiction,
      'General Non-fiction' => l10n.kostvBookGenreGeneralNonFiction,
      'Historical Fiction' => l10n.kostvBookGenreHistoricalFiction,
      'Horror & Supernatural Fiction' => l10n.kostvBookGenreHorrorSupernaturalFiction,
      'Humor' => l10n.kostvBookGenreHumor,
      'Humorous Fiction' => l10n.kostvBookGenreHumorousFiction,
      'Mystery & Detective Stories' => l10n.kostvBookGenreMysteryDetectiveStories,
      'Mythology' => l10n.kostvBookGenreMythology,
      'Nature' => l10n.kostvBookGenreNature,
      'Naval Fiction' => l10n.kostvBookGenreNavalFiction,
      'Philosophy' => l10n.kostvBookGenrePhilosophy,
      'Plays' => l10n.kostvBookGenrePlays,
      'Poetry' => l10n.kostvBookGenrePoetry,
      'Religion' => l10n.kostvBookGenreReligion,
      'Romance' => l10n.kostvBookGenreRomance,
      'Satire' => l10n.kostvBookGenreSatire,
      'Science Fiction' => l10n.kostvBookGenreScienceFiction,
      'Short Stories' => l10n.kostvBookGenreShortStories,
      'Travel & Geography' => l10n.kostvBookGenreTravelGeography,
      'Tragedy' => l10n.kostvBookGenreTragedy,
      'War & Military Fiction' => l10n.kostvBookGenreWarMilitaryFiction,
      'Westerns' => l10n.kostvBookGenreWesterns,
      _ => null,
    };

/// A LibriVox genre's label, the genre itself when it has none.
String displayAudiobookGenre(String genre, [AppLocalizations? l10n]) =>
    bookGenreLabel(l10n ?? currentAppLocalizations(), genre) ?? genre;

String displayBookGenre(String slug, [AppLocalizations? l10n]) {
  final label = bookGenreLabel(l10n ?? currentAppLocalizations(), slug);
  if (label != null) return label;

  final decoded = Uri.decodeComponent(slug);
  final normalized = decoded.replaceAll(RegExp(r'_+'), ' ').replaceAll(':', ' ');
  final words = normalized
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .toList();
  return words.join(' ');
}

class DiscoverBook {
  final String identity;
  final String title;
  final String author;
  final String? coverUrl;
  final String? workKey;
  final int? firstPublishYear;

  const DiscoverBook({
    required this.identity,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.workKey,
    required this.firstPublishYear,
  });

  factory DiscoverBook.fromOpenLibraryMap(Map<String, dynamic> map) {
    final key = map['key'] as String? ?? '';
    final title = (map['title'] as String? ?? '').trim();
    final authorNamesFromSearch =
        (map['author_name'] as List?)
            ?.whereType<String>()
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toList() ??
        const <String>[];
    final authorNamesFromWorks =
        (map['authors'] as List?)
            ?.whereType<Map>()
            .map((a) => (a['name'] as String? ?? '').trim())
            .where((name) => name.isNotEmpty)
            .toList() ??
        const <String>[];
    // Kos TV: with no author, "Unknown Author" in the app's language.
    final author = authorNamesFromSearch.isNotEmpty
        ? authorNamesFromSearch.first
        : authorNamesFromWorks.isNotEmpty
        ? authorNamesFromWorks.first
        : currentAppLocalizations().unknownAuthor;

    final coverId =
        (map['cover_i'] as num?)?.toInt() ?? (map['cover_id'] as num?)?.toInt();
    final coverUrl = coverId != null
        ? 'https://covers.openlibrary.org/b/id/$coverId-M.jpg'
        : null;
    final firstPublishYear = (map['first_publish_year'] as num?)?.toInt();

    return DiscoverBook(
      identity: key.isNotEmpty ? key : '$title::$author',
      title: title,
      author: author,
      coverUrl: coverUrl,
      workKey: key.startsWith('/works/') ? key : null,
      firstPublishYear: firstPublishYear,
    );
  }
}

class LibrivoxBook {
  final String id;
  final String title;
  final String authorName;
  final List<String> isbns;
  final String? description;
  final String? language;
  final int? copyrightYear;
  final int? sectionCount;
  final List<String> genres;
  final List<String> readerNames;
  final String? archiveUrl;
  final String? zipUrl;
  final String? rssUrl;
  final String? librivoxUrl;
  final int totalTimeSecs;

  const LibrivoxBook({
    required this.id,
    required this.title,
    required this.authorName,
    required this.isbns,
    required this.description,
    required this.language,
    required this.copyrightYear,
    required this.sectionCount,
    required this.genres,
    required this.readerNames,
    required this.archiveUrl,
    required this.zipUrl,
    required this.rssUrl,
    required this.librivoxUrl,
    required this.totalTimeSecs,
  });

  factory LibrivoxBook.fromMap(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString().trim();
    final title = (map['title'] as String? ?? '').trim();
    final authors = (map['authors'] as List?) ?? const [];
    final authorName =
        authors
            .whereType<Map>()
            .map((a) {
              final first = (a['first_name'] as String? ?? '').trim();
              final last = (a['last_name'] as String? ?? '').trim();
              return [first, last].where((n) => n.isNotEmpty).join(' ');
            })
            .where((name) => name.isNotEmpty)
            .firstOrNull ??
        currentAppLocalizations().unknownAuthor;
    final isbns = <String>{};
    String? normalizeIsbn(dynamic raw) {
      final value = (raw ?? '').toString().trim();
      if (value.isEmpty) return null;
      final normalized = value
          .replaceAll(RegExp(r'[^0-9Xx]'), '')
          .toUpperCase();
      if (normalized.length == 10 || normalized.length == 13) {
        return normalized;
      }
      return null;
    }

    for (final key in const [
      'isbn',
      'isbn13',
      'isbn_13',
      'isbn10',
      'isbn_10',
    ]) {
      final raw = map[key];
      if (raw is List) {
        for (final item in raw) {
          final parsed = normalizeIsbn(item);
          if (parsed != null) isbns.add(parsed);
        }
      } else {
        final parsed = normalizeIsbn(raw);
        if (parsed != null) isbns.add(parsed);
      }
    }
    final description = (map['description'] as String?)?.trim();
    final language = (map['language'] as String?)?.trim();

    int? parseField(dynamic v) => v is num
        ? v.toInt()
        : v is String
        ? int.tryParse(v)
        : null;
    final copyrightYear = parseField(map['copyright_year']);
    final sectionCount = parseField(map['num_sections']);
    final totalTimeSecs = parseField(map['totaltimesecs']) ?? 0;
    final genres = ((map['genres'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((g) => (g['name'] as String? ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    final readerNames = ((map['readers'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((reader) {
          final first = (reader['first_name'] as String? ?? '').trim();
          final last = (reader['last_name'] as String? ?? '').trim();
          final display = (reader['display_name'] as String? ?? '').trim();
          if (display.isNotEmpty) return display;
          return [first, last].where((n) => n.isNotEmpty).join(' ');
        })
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();

    String? parseUrl(String key) {
      final v = (map[key] as String? ?? '').trim();
      return v.isEmpty ? null : v;
    }

    final archiveUrl = parseUrl('url_iarchive');
    final zipUrl = parseUrl('url_zip_file');
    final rssUrl = parseUrl('url_rss');
    final librivoxUrl = parseUrl('url_librivox');

    return LibrivoxBook(
      id: id,
      title: title,
      authorName: authorName,
      isbns: isbns.toList(),
      description: description,
      language: language,
      copyrightYear: copyrightYear,
      sectionCount: sectionCount,
      genres: genres,
      readerNames: readerNames,
      archiveUrl: archiveUrl,
      zipUrl: zipUrl,
      rssUrl: rssUrl,
      librivoxUrl: librivoxUrl,
      totalTimeSecs: totalTimeSecs,
    );
  }

  String? get preferredIsbn => isbns.firstOrNull;

  String get formattedDuration {
    if (totalTimeSecs <= 0) return '';
    if (totalTimeSecs < 60) return '${totalTimeSecs}s';
    return formatRuntimeShort(Duration(seconds: totalTimeSecs));
  }
}
