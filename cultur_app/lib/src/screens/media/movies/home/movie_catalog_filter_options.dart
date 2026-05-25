import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_category.dart';
import 'package:yamtrack/src/screens/library/widgets/library_filter_option.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';
import 'package:yamtrack/src/utils/home_categories.dart';

/// TMDB movie genre labels accepted by `GET /catalog/movies?genre=…`.
const kTmdbMovieCatalogGenres = <String>[
  'Action',
  'Adventure',
  'Animation',
  'Comedy',
  'Crime',
  'Documentary',
  'Drama',
  'Family',
  'Fantasy',
  'History',
  'Horror',
  'Music',
  'Mystery',
  'Romance',
  'Science Fiction',
  'TV Movie',
  'Thriller',
  'War',
  'Western',
];

const _movieBrowseSections = <String, String>{
  'popular': 'Popular',
  'now_playing': 'Now playing',
  'top_rated': 'Top rated',
  'upcoming': 'Upcoming',
};

List<LibraryFilterOption> buildMovieCatalogFilterOptions({
  required String section,
  required String genre,
  required ValueChanged<String> onSectionChanged,
  required ValueChanged<String> onGenreChanged,
}) {
  final sectionLabel = _movieBrowseSections[section] ?? 'Browse';
  final genreLabels = {for (final g in kTmdbMovieCatalogGenres) g: g};

  return [
    LibraryFilterOption(
      id: 'section',
      label: sectionLabel,
      isActive: section != 'popular',
      onPick: (ctx) => showMultiSelectKeySheet(
        ctx,
        title: 'Browse',
        keyLabels: _movieBrowseSections,
        selected: {section},
        onApply: (next) {
          if (next.isEmpty) {
            onSectionChanged('popular');
          } else {
            onSectionChanged(
              normalizedCatalogSection(CatalogBrowseKind.movies, next.first),
            );
          }
        },
      ),
    ),
    LibraryFilterOption(
      id: 'genre',
      label: genre.isEmpty ? 'Genre' : genre,
      isActive: genre.isNotEmpty,
      onPick: (ctx) => showMultiSelectKeySheet(
        ctx,
        title: 'Genre',
        keyLabels: genreLabels,
        selected: genre.isEmpty ? <String>{} : {genre},
        onApply: (next) {
          if (next.isEmpty) {
            onGenreChanged('');
          } else {
            onGenreChanged(next.first);
          }
        },
      ),
    ),
  ];
}
