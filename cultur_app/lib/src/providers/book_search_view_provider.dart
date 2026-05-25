import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:yamtrack/src/providers/search_provider.dart';

enum BookSearchViewMode {
  list,
  grid,
}

BookSearchViewMode? parseBookSearchViewMode(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  for (final value in BookSearchViewMode.values) {
    if (value.name == raw) {
      return value;
    }
  }
  if (raw == 'detailed' || raw == 'compact' || raw == 'posters') {
    return BookSearchViewMode.list;
  }
  if (raw == 'grid') {
    return BookSearchViewMode.grid;
  }
  return null;
}

extension BookSearchViewModeStyle on BookSearchViewMode {
  String get label => switch (this) {
        BookSearchViewMode.list => 'List',
        BookSearchViewMode.grid => 'Grid',
      };

  IconData get icon => switch (this) {
        BookSearchViewMode.list => Icons.view_list_outlined,
        BookSearchViewMode.grid => Icons.grid_view_rounded,
      };
}

final bookSearchViewModeProvider =
    StateProvider<BookSearchViewMode>((ref) => BookSearchViewMode.list);

final bookSearchGridColumnsProvider = movieSearchGridColumnsProvider;
