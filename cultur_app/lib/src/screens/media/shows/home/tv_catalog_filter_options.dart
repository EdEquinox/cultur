import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_category.dart';
import 'package:yamtrack/src/screens/library/widgets/library_filter_option.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';
import 'package:yamtrack/src/utils/home_categories.dart';

/// TMDB TV genre labels accepted by `GET /catalog/tv?genre=…`.
const kTmdbTvCatalogGenres = <String>[
  'Action & Adventure',
  'Animation',
  'Comedy',
  'Crime',
  'Documentary',
  'Drama',
  'Family',
  'Kids',
  'Mystery',
  'News',
  'Reality',
  'Sci-Fi & Fantasy',
  'Soap',
  'Talk',
  'War & Politics',
  'Western',
];

const _tvBrowseSections = <String, String>{
  'popular': 'Popular',
  'on_the_air': 'On the air',
  'top_rated': 'Top rated',
  'airing_today': 'Airing today',
};

List<LibraryFilterOption> buildTvCatalogFilterOptions({
  required String section,
  required String genre,
  required ValueChanged<String> onSectionChanged,
  required ValueChanged<String> onGenreChanged,
}) {
  final sectionLabel = _tvBrowseSections[section] ?? 'Browse';
  final genreLabels = {for (final g in kTmdbTvCatalogGenres) g: g};

  return [
    LibraryFilterOption(
      id: 'section',
      label: sectionLabel,
      isActive: section != 'popular',
      onPick: (ctx) => showMultiSelectKeySheet(
        ctx,
        title: 'Browse',
        keyLabels: _tvBrowseSections,
        selected: {section},
        onApply: (next) {
          if (next.isEmpty) {
            onSectionChanged('popular');
          } else {
            onSectionChanged(
              normalizedCatalogSection(CatalogBrowseKind.tv, next.first),
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
