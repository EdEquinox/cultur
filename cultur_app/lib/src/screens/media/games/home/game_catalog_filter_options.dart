import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/games/game_filter_option.dart';
import 'package:yamtrack/src/screens/library/widgets/library_filter_option.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

List<LibraryFilterOption> buildGameCatalogFilterOptions({
  required GameCatalogFilters filters,
  required Set<String> platformIds,
  required Set<String> genreIds,
  required Set<String> gameModeIds,
  required Set<String> playerPerspectiveIds,
  required String gameTypeId,
  required ValueChanged<Set<String>> onPlatformsChanged,
  required ValueChanged<Set<String>> onGenresChanged,
  required ValueChanged<Set<String>> onGameModesChanged,
  required ValueChanged<Set<String>> onPlayerPerspectivesChanged,
  required ValueChanged<String> onGameTypeChanged,
}) {
  Map<String, String> labelsFor(List<GameFilterOption> options) {
    return {for (final o in options) o.id: o.name};
  }

  String? nameForId(List<GameFilterOption> options, String id) {
    for (final o in options) {
      if (o.id == id) {
        return o.name;
      }
    }
    return null;
  }

  final options = <LibraryFilterOption>[];

  if (filters.platforms.isNotEmpty) {
    options.add(
      LibraryFilterOption(
        id: 'platform',
        label: platformIds.isEmpty ? 'Platform' : 'Platform (${platformIds.length})',
        isActive: platformIds.isNotEmpty,
        onPick: (ctx) => showMultiSelectKeySheet(
          ctx,
          title: 'Platform',
          keyLabels: labelsFor(filters.platforms),
          selected: platformIds,
          onApply: onPlatformsChanged,
        ),
      ),
    );
  }

  if (filters.genres.isNotEmpty) {
    options.add(
      LibraryFilterOption(
        id: 'genre',
        label: genreIds.isEmpty ? 'Genre' : 'Genre (${genreIds.length})',
        isActive: genreIds.isNotEmpty,
        onPick: (ctx) => showMultiSelectKeySheet(
          ctx,
          title: 'Genre',
          keyLabels: labelsFor(filters.genres),
          selected: genreIds,
          onApply: onGenresChanged,
        ),
      ),
    );
  }

  if (filters.gameModes.isNotEmpty) {
    options.add(
      LibraryFilterOption(
        id: 'game_mode',
        label: gameModeIds.isEmpty ? 'Game mode' : 'Game mode (${gameModeIds.length})',
        isActive: gameModeIds.isNotEmpty,
        onPick: (ctx) => showMultiSelectKeySheet(
          ctx,
          title: 'Game mode',
          keyLabels: labelsFor(filters.gameModes),
          selected: gameModeIds,
          onApply: onGameModesChanged,
        ),
      ),
    );
  }

  if (filters.playerPerspectives.isNotEmpty) {
    options.add(
      LibraryFilterOption(
        id: 'player_perspective',
        label: playerPerspectiveIds.isEmpty
            ? 'Player perspective'
            : 'Player perspective (${playerPerspectiveIds.length})',
        isActive: playerPerspectiveIds.isNotEmpty,
        onPick: (ctx) => showMultiSelectKeySheet(
          ctx,
          title: 'Player perspective',
          keyLabels: labelsFor(filters.playerPerspectives),
          selected: playerPerspectiveIds,
          onApply: onPlayerPerspectivesChanged,
        ),
      ),
    );
  }

  if (filters.gameTypes.isNotEmpty) {
    final typeLabel = gameTypeId.isEmpty
        ? 'Game type'
        : (nameForId(filters.gameTypes, gameTypeId) ?? 'Game type');
    options.add(
      LibraryFilterOption(
        id: 'game_type',
        label: typeLabel,
        isActive: gameTypeId.isNotEmpty,
        onPick: (ctx) => showMultiSelectKeySheet(
          ctx,
          title: 'Game type',
          keyLabels: labelsFor(filters.gameTypes),
          selected: gameTypeId.isEmpty ? <String>{} : {gameTypeId},
          onApply: (next) {
            if (next.isEmpty) {
              onGameTypeChanged('');
            } else {
              onGameTypeChanged(next.first);
            }
          },
        ),
      ),
    );
  }

  return options;
}
