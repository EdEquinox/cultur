import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:yamtrack/src/providers/search_provider.dart';

enum GameSearchViewMode {
  list,
  grid,
}

GameSearchViewMode? parseGameSearchViewMode(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  for (final value in GameSearchViewMode.values) {
    if (value.name == raw) {
      return value;
    }
  }
  if (raw == 'detailed' || raw == 'compact' || raw == 'posters') {
    return GameSearchViewMode.list;
  }
  if (raw == 'grid') {
    return GameSearchViewMode.grid;
  }
  return null;
}

extension GameSearchViewModeStyle on GameSearchViewMode {
  String get label => switch (this) {
        GameSearchViewMode.list => 'List',
        GameSearchViewMode.grid => 'Grid',
      };

  IconData get icon => switch (this) {
        GameSearchViewMode.list => Icons.view_list_outlined,
        GameSearchViewMode.grid => Icons.grid_view_rounded,
      };
}

final gameSearchViewModeProvider =
    StateProvider<GameSearchViewMode>((ref) => GameSearchViewMode.list);

/// Grid column count shared with movie search preference.
final gameSearchGridColumnsProvider = movieSearchGridColumnsProvider;
