import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

final movieSearchGridColumnsProvider = StateProvider<int>((ref) => 2);

enum MovieSearchViewMode {
  list,
  grid,
}

MovieSearchViewMode? parseMovieSearchViewMode(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  for (final value in MovieSearchViewMode.values) {
    if (value.name == raw) {
      return value;
    }
  }
  if (raw == 'detailed' || raw == 'compact' || raw == 'posters') {
    return MovieSearchViewMode.list;
  }
  if (raw == 'grid') {
    return MovieSearchViewMode.grid;
  }
  return null;
}

extension MovieSearchViewModeStyle on MovieSearchViewMode {
  String get label => switch (this) {
        MovieSearchViewMode.list => 'List',
        MovieSearchViewMode.grid => 'Grid',
      };

  IconData get icon => switch (this) {
        MovieSearchViewMode.list => Icons.view_list_outlined,
        MovieSearchViewMode.grid => Icons.grid_view_rounded,
      };
}

final movieSearchViewModeProvider =
    StateProvider<MovieSearchViewMode>((ref) => MovieSearchViewMode.list);
