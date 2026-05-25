import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/games_home_providers.dart';
import 'package:yamtrack/src/screens/home/widgets/category_home_manual_create_bar.dart';
import 'package:yamtrack/src/screens/home/widgets/pending_imports_home_section.dart';
import 'package:yamtrack/src/utils/library_utils.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/games_tracking_shelf_section.dart';
import 'package:yamtrack/src/screens/home/widgets/collected_lent_home_section.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/stash_events_timeline_section.dart';

/// Home tab for Games: library shelves + Stash industry events.
class GamesCategoryHomeBody extends ConsumerWidget {
  const GamesCategoryHomeBody({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(gamesPlayingShelfProvider(username));
    final nextToPlay = ref.watch(gamesNextToPlayShelfProvider(username));
    return Column(
      children: [
        PendingImportsHomeSection(
          username: username,
          scope: LibraryMediaScope.game,
          emptyMessage:
              'Games that could not be matched during import appear here. Open one and use Search catalog to link it.',
          onSeeAll: () => context.push(
            '${LibraryMediaScope.game.libraryBasePath}/lists/${BuiltInGameLists.pendingImportsListId}',
          ),
        ),
        GamesTrackingShelfSection(
          title: 'Playing',
          icon: Icons.play_circle_outline,
          state: playing,
          emptyMessage:
              'Mark games as Playing from a game page or your Library → Playing tab.',
          onSeeAll: () => context.push(
            LibraryMediaScope.game.path('doing'),
          ),
        ),
        const SizedBox(height: 16),
        GamesTrackingShelfSection(
          title: 'Next to play',
          icon: Icons.sports_esports_outlined,
          state: nextToPlay,
          emptyMessage:
              'Add games to Later or mark them as priority — they show up here.',
          onSeeAll: () => context.push(
            LibraryMediaScope.game.path('later'),
          ),
          badgeForItem: (item) {
            if (item.inPriority) {
              return (icon: Icons.push_pin, tooltip: 'Priority');
            }
            if (item.inWatchlist) {
              return (icon: Icons.bookmark, tooltip: 'Later');
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        const StashEventsTimelineSection(),
        const CollectedLentHomeSection(mediaScope: LibraryMediaScope.game),
        CategoryHomeManualCreateBar(
          scope: LibraryMediaScope.game,
          username: username,
        ),
      ],
    );
  }
}
