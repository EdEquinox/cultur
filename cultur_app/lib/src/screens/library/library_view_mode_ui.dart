import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/library/library_enums.dart';

extension LibraryViewModeUi on LibraryViewMode {
  String get label => switch (this) {
        LibraryViewMode.detailed => 'Detailed list',
        LibraryViewMode.compact => 'Compact list',
        LibraryViewMode.grid => 'Grid',
        LibraryViewMode.posters => 'Poster wall',
      };

  IconData get icon => switch (this) {
        LibraryViewMode.detailed => Icons.view_agenda_outlined,
        LibraryViewMode.compact => Icons.view_list_outlined,
        LibraryViewMode.grid => Icons.grid_view_rounded,
        LibraryViewMode.posters => Icons.dashboard_customize_outlined,
      };
}
