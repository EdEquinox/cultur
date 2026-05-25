import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/screens/home/widgets/latest_release_section.dart';
import 'package:yamtrack/src/screens/home/widgets/next_to_watch_shelf_section.dart';
import 'package:yamtrack/src/screens/home/widgets/upcoming_timeline_section.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/catalog_shelf_providers.dart';
import 'package:yamtrack/src/providers/next_to_watch_providers.dart';
import 'package:yamtrack/src/screens/home/widgets/collected_lent_home_section.dart';
import 'package:yamtrack/src/screens/home/widgets/category_home_manual_create_bar.dart';
import 'package:yamtrack/src/screens/home/widgets/pending_imports_home_section.dart';
import 'package:yamtrack/src/utils/library_utils.dart';

/// Home tab rails for the Movies category (catalog).
class MoviesCategoryHomeBody extends ConsumerWidget {
  const MoviesCategoryHomeBody({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextToWatch = ref.watch(nextToWatchShelfProvider(username));
    final homeShelves = ref.watch(movieHomeShelvesProvider);
    final latest = movieHomeShelfNowPlaying(homeShelves);
    final upcoming = movieHomeShelfUpcoming(homeShelves);

    return Column(
      children: [
        PendingImportsHomeSection(
          username: username,
          scope: LibraryMediaScope.movie,
          emptyMessage:
              'Movies that could not be matched during AVA import appear here. Open one and use Search catalog to link it.',
          onSeeAll: () => context.push(
            '${LibraryMediaScope.movie.libraryBasePath}/lists/${BuiltInMovieLists.pendingImportsListId}',
          ),
        ),
        NextToWatchShelfSection(
          title: 'Next to watch',
          state: nextToWatch,
          username: username,
          emptyMessage:
              'Pin movies to your priority queue or add recent releases to “Movies in cinema”. Titles are added to your watchlist automatically when you use those pins.',
          onSeeAll: () => context.push('/shelves/movies/next-to-watch'),
        ),
        const SizedBox(height: 16),
        LatestReleaseSection(
          title: 'Latest releases',
          icon: Icons.movie_creation_outlined,
          state: latest,
          emptyMessage: 'There are no recent releases to show yet.',
          onSeeAll: () => context.push('/category/movies?section=now_playing'),
        ),
        const SizedBox(height: 16),
        UpcomingTimelineSection(
          title: 'Upcoming',
          icon: Icons.upcoming_outlined,
          state: upcoming,
          paginateMovies: true,
          emptyMessage: 'There are no upcoming movies to show yet.',
          onSeeAll: () => context.push('/shelves/movies/upcoming'),
        ),
        const CollectedLentHomeSection(mediaScope: LibraryMediaScope.movie),
        CategoryHomeManualCreateBar(
          scope: LibraryMediaScope.movie,
          username: username,
        ),
      ],
    );
  }
}
