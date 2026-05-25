import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/boardgames_home_providers.dart';
import 'package:yamtrack/src/screens/home/widgets/latest_release_section.dart';
import 'package:yamtrack/src/screens/home/widgets/collected_lent_home_section.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/games_tracking_shelf_section.dart';
import 'package:yamtrack/src/screens/home/widgets/category_home_manual_create_bar.dart';

/// Home tab for board games: BGG hot list + wishlist priority shelf.
class BoardgamesCategoryHomeBody extends ConsumerWidget {
  const BoardgamesCategoryHomeBody({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final popular = ref.watch(boardgamesPopularProvider);
    final nextToTry = ref.watch(boardgamesNextToTryShelfProvider(username));

    return Column(
      children: [
        GamesTrackingShelfSection(
          title: 'Next to try',
          icon: Icons.casino_outlined,
          state: nextToTry,
          emptyMessage:
              'Add board games to Later or mark them as priority — they show up here.',
          onSeeAll: () => context.push(
            LibraryMediaScope.boardgame.path('later'),
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
        LatestReleaseSection(
          title: 'Popular on BGG',
          icon: Icons.local_fire_department_outlined,
          state: popular,
          emptyMessage: 'Could not load the BGG hot list right now.',
          onSeeAll: () => context.push('/category/board-games'),
        ),
        
        const CollectedLentHomeSection(mediaScope: LibraryMediaScope.boardgame),
        CategoryHomeManualCreateBar(
          scope: LibraryMediaScope.boardgame,
          username: username,
        ),
      ],
    );
  }
}
