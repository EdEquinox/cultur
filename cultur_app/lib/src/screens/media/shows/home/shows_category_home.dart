import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/screens/home/widgets/next_to_watch_shelf_section.dart';
import 'package:yamtrack/src/screens/home/widgets/tv_next_up_section.dart';
import 'package:yamtrack/src/screens/home/widgets/upcoming_timeline_section.dart';

import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/catalog_shelf_providers.dart';
import 'package:yamtrack/src/providers/next_to_watch_providers.dart';
import 'package:yamtrack/src/screens/home/widgets/collected_lent_home_section.dart';
import 'package:yamtrack/src/screens/home/widgets/category_home_manual_create_bar.dart';
import 'package:yamtrack/src/screens/home/widgets/pending_imports_home_section.dart';
import 'package:yamtrack/src/utils/library_utils.dart';

/// Home tab rails for the TV Shows category (catalog).
class ShowsCategoryHomeBody extends ConsumerWidget {
  const ShowsCategoryHomeBody({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeShelves = ref.watch(tvHomeShelvesProvider(username));
    final nextUp = tvHomeShelfNextUp(homeShelves);
    final upcoming = tvHomeShelfUpcomingEpisodes(homeShelves);
    final nextToWatchTv = ref.watch(tvNextToWatchShelfProvider(username));
    return Column(
      children: [
        PendingImportsHomeSection(
          username: username,
          scope: LibraryMediaScope.tv,
          emptyMessage:
              'Series that could not be matched during AVA import appear here. Open one and use Search catalog to link it.',
          onSeeAll: () => context.push(
            '${LibraryMediaScope.tv.libraryBasePath}/lists/${BuiltInTvLists.pendingImportsListId}',
          ),
        ),
        const CollectedLentHomeSection(mediaScope: LibraryMediaScope.tv),
        TvNextUpSection(
          title: 'Continue watching',
          icon: Icons.playlist_play_outlined,
          state: nextUp,
          username: username,
          emptyMessage:
              '',
          onSeeAll: () => context.push('/shelves/tv/continue-watching'),
        ),
        const SizedBox(height: 16),
        NextToWatchShelfSection(
          title: 'Next to watch',
          state: nextToWatchTv,
          username: username,
          emptyMessage:
              '',
          onSeeAll: () => context.push('/shelves/tv/next-to-watch'),
        ),
        const SizedBox(height: 16),
        UpcomingTimelineSection(
          title: 'Upcoming',
          icon: Icons.upcoming_outlined,
          state: upcoming,
          emptyMessage:
              '',
          onSeeAll: () => context.push('/shelves/tv/upcoming'),
        ),
        CategoryHomeManualCreateBar(
          scope: LibraryMediaScope.tv,
          username: username,
        ),
      ],
    );
  }
}
