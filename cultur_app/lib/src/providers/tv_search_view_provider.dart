import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:yamtrack/src/providers/search_provider.dart';

enum TvSearchViewMode {
  list,
  grid,
}

TvSearchViewMode? parseTvSearchViewMode(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  for (final value in TvSearchViewMode.values) {
    if (value.name == raw) {
      return value;
    }
  }
  if (raw == 'detailed' || raw == 'compact' || raw == 'posters') {
    return TvSearchViewMode.list;
  }
  if (raw == 'grid') {
    return TvSearchViewMode.grid;
  }
  return null;
}

extension TvSearchViewModeStyle on TvSearchViewMode {
  String get label => switch (this) {
        TvSearchViewMode.list => 'List',
        TvSearchViewMode.grid => 'Grid',
      };

  IconData get icon => switch (this) {
        TvSearchViewMode.list => Icons.view_list_outlined,
        TvSearchViewMode.grid => Icons.grid_view_rounded,
      };
}

final tvSearchViewModeProvider =
    StateProvider<TvSearchViewMode>((ref) => TvSearchViewMode.list);

/// Collected-tab grid uses 3 columns; reuse movie search column preference when > 2.
final tvSearchGridColumnsProvider = movieSearchGridColumnsProvider;
