import 'package:flutter/material.dart';
import 'package:yamtrack/src/screens/library/widgets/library_filter_option.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

/// Open Library language codes for book search filters.
const kBookCatalogLanguageLabels = <String, String>{
  'eng': 'English',
  'por': 'Portuguese',
  'spa': 'Spanish',
  'fre': 'French',
  'ger': 'German',
  'ita': 'Italian',
  'dut': 'Dutch',
  'rus': 'Russian',
  'jpn': 'Japanese',
  'chi': 'Chinese',
  'pol': 'Polish',
  'cat': 'Catalan',
  'gle': 'Irish',
};

/// Common Open Library subjects used in search filters.
const kBookCatalogSubjects = <String>[
  'Fiction',
  'Fantasy',
  'Science Fiction',
  'Mystery',
  'Romance',
  'History',
  'Biography',
  'Poetry',
  'Horror',
  'Thriller',
  'Children',
  'Young Adult',
];

Map<String, String> bookCatalogYearLabels() {
  final now = DateTime.now().year;
  return {
    for (var year = now; year >= 1950; year--) year.toString(): year.toString(),
  };
}

List<LibraryFilterOption> buildBookCatalogFilterOptions({
  required String language,
  required String publishYear,
  required String genre,
  required ValueChanged<String> onLanguageChanged,
  required ValueChanged<String> onPublishYearChanged,
  required ValueChanged<String> onGenreChanged,
}) {
  final yearLabels = bookCatalogYearLabels();
  final subjectLabels = {for (final s in kBookCatalogSubjects) s: s};

  return [
    LibraryFilterOption(
      id: 'language',
      label: language.isEmpty
          ? 'Language'
          : (kBookCatalogLanguageLabels[language] ?? language),
      isActive: language.isNotEmpty,
      onPick: (ctx) => showMultiSelectKeySheet(
        ctx,
        title: 'Language',
        keyLabels: kBookCatalogLanguageLabels,
        selected: language.isEmpty ? <String>{} : {language},
        onApply: (next) {
          onLanguageChanged(next.isEmpty ? '' : next.first);
        },
      ),
    ),
    LibraryFilterOption(
      id: 'year',
      label: publishYear.isEmpty ? 'Year' : publishYear,
      isActive: publishYear.isNotEmpty,
      onPick: (ctx) => showMultiSelectKeySheet(
        ctx,
        title: 'Year',
        keyLabels: yearLabels,
        selected: publishYear.isEmpty ? <String>{} : {publishYear},
        onApply: (next) {
          onPublishYearChanged(next.isEmpty ? '' : next.first);
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
        keyLabels: subjectLabels,
        selected: genre.isEmpty ? <String>{} : {genre},
        onApply: (next) {
          onGenreChanged(next.isEmpty ? '' : next.first);
        },
      ),
    ),
  ];
}
