import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/library/library_enums.dart';
import 'package:yamtrack/src/screens/navbar/floating_search_fab.dart';

import 'bar_button.dart';

enum FloatingLibraryDestination {
  home,
  personalLists,
  later,
  buy,
  finished,
  owned,
  doing,
  left,
}

class FloatingLibraryNav extends StatelessWidget {
  const FloatingLibraryNav({
    required this.currentDestination,
    this.mediaScope = LibraryMediaScope.movie,
    super.key,
  });

  final FloatingLibraryDestination? currentDestination;
  final LibraryMediaScope mediaScope;

  /// Nav row height (without safe area or search FAB).
  static const double barHeight = 40;

  /// Recommended bottom padding for scrollables above this bar + search FAB.
  static const double scrollBottomInset = 148;

  static FloatingLibraryDestination _destinationForKind(LibraryCollectionKind kind) {
    return switch (kind) {
      LibraryCollectionKind.later => FloatingLibraryDestination.later,
      LibraryCollectionKind.doing => FloatingLibraryDestination.doing,
      LibraryCollectionKind.finished => FloatingLibraryDestination.finished,
      LibraryCollectionKind.owned => FloatingLibraryDestination.owned,
      LibraryCollectionKind.buy => FloatingLibraryDestination.buy,
      LibraryCollectionKind.left => FloatingLibraryDestination.left,
    };
  }

  @override
  Widget build(BuildContext context) {
    Widget slot({
      required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: FloatingLibraryNavButton(
            icon: icon,
            label: label,
            selected: selected,
            onTap: onTap,
          ),
        ),
      );
    }

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 2, bottom: 10),
              child: FloatingSearchFab(mediaScope: mediaScope),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                slot(
                  icon: Icons.list_alt_outlined,
                  label: 'Lists',
                  selected: currentDestination == FloatingLibraryDestination.personalLists,
                  onTap: () => context.go(mediaScope.path('lists')),
                ),
                for (final kind in mediaScope.collectionKinds)
                  slot(
                    icon: mediaScope.collectionNavLabel(kind).$1,
                    label: mediaScope.collectionNavLabel(kind).$2,
                    selected: currentDestination == _destinationForKind(kind),
                    onTap: () => context.go(mediaScope.path(kind.collectionPathSegment)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
