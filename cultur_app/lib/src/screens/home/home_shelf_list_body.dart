import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/providers/catalog_shelf_providers.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/providers/next_to_watch_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/home/widgets/next_to_watch_poster_card.dart';
import 'package:yamtrack/src/screens/home/widgets/tv_next_up_episode_row.dart';
import 'package:yamtrack/src/screens/home/widgets/maybe_browse_more.dart';
import 'package:yamtrack/src/models/games/stash_game_event.dart';
import 'package:yamtrack/src/providers/games_home_providers.dart';
import 'package:yamtrack/src/screens/home/widgets/upcoming_shelf_list.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/stash_events_shelf_list.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/library_item_search.dart';

class HomeShelfListBody extends ConsumerWidget {
  const HomeShelfListBody({
    super.key,
    required this.scope,
    required this.shelf,
    required this.username,
    this.searchQuery = '',
  });

  final String scope;
  final String shelf;
  final String username;
  final String searchQuery;

  bool _matches(CatalogItem item) => catalogItemMatchesLibrarySearch(item, searchQuery);

  bool _matchesEvent(StashGameEvent event) {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) {
      return true;
    }
    return event.title.toLowerCase().contains(q);
  }

  Widget _noSearchMatches() {
    return Center(
      child: EmptyState(
        title: 'No matches',
        message: 'Nothing matches your search.',
        icon: Icons.search_off_outlined,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '$scope:$shelf';

    if (key == 'tv:continue-watching') {
      final async = ref.watch(tvHomeShelvesProvider(username));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e),
        data: (home) {
          var items = catalogContinueWatchingSortedNewestFirst(home.nextUp);
          if (searchQuery.trim().isNotEmpty) {
            items = items.where(_matches).toList();
          }
          if (items.isEmpty && searchQuery.trim().isNotEmpty) {
            return _noSearchMatches();
          }
          if (items.isEmpty) {
            return Center(
              child: EmptyState(
                title: 'Nothing in progress',
                message:
                    'Mark an episode as watched on a series you follow — the next one will appear here.',
                icon: Icons.playlist_play_outlined,
              ),
            );
          }
          return maybeBrowseMore(
            context,
            scope: scope,
            itemCount: items.length,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                return TvNextUpEpisodeRow(
                  item: items[i],
                  username: username,
                );
              },
            ),
          );
        },
      );
    }

    if (key == 'tv:next-to-watch') {
      final async = ref.watch(tvNextToWatchShelfProvider(username));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e),
        data: (items) {
          var filtered = items;
          if (searchQuery.trim().isNotEmpty) {
            filtered = items
                .where((e) => catalogItemMatchesLibrarySearch(e.media, searchQuery))
                .toList();
          }
          if (filtered.isEmpty && searchQuery.trim().isNotEmpty) {
            return _noSearchMatches();
          }
          if (filtered.isEmpty) {
            return Center(
              child: EmptyState(
                title: 'Nothing queued',
                message:
                    'Pin TV shows to your priority queue in the Library — they appear here.',
                icon: Icons.push_pin_outlined,
              ),
            );
          }
          return maybeBrowseMore(
            context,
            scope: scope,
            itemCount: filtered.length,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: NextToWatchPosterCard.gridChildAspectRatio,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                return NextToWatchPosterCard(
                  item: filtered[i],
                  username: username,
                  inGrid: true,
                  onTap: () => context.push(catalogItemDetailPath(filtered[i].media)),
                );
              },
            ),
          );
        },
      );
    }

    if (key == 'tv:upcoming') {
      final async = ref.watch(tvHomeShelvesProvider(username));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e),
        data: (home) {
          var items = home.upcomingEpisodes.items
              .where(catalogItemIsUpcomingRelease)
              .toList();
          if (searchQuery.trim().isNotEmpty) {
            items = items.where(_matches).toList();
          }
          if (items.isEmpty && searchQuery.trim().isNotEmpty) {
            return _noSearchMatches();
          }
          if (items.isEmpty) {
            return Center(
              child: EmptyState(
                title: 'No upcoming episodes',
                message:
                    'Follow series in progress or on your watchlist — future air dates show here.',
                icon: Icons.upcoming_outlined,
              ),
            );
          }
          return maybeBrowseMore(
            context,
            scope: scope,
            itemCount: items.length,
            child: UpcomingShelfList(
              initialItems: items,
              onItemTap: (item) => context.push(catalogItemDetailPath(item)),
            ),
          );
        },
      );
    }

    if (key == 'movies:next-to-watch') {
      final async = ref.watch(nextToWatchShelfProvider(username));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e),
        data: (items) {
          var movies = items.where((e) => e.media.mediaType == 'movie').toList();
          if (searchQuery.trim().isNotEmpty) {
            movies = movies
                .where((e) => catalogItemMatchesLibrarySearch(e.media, searchQuery))
                .toList();
          }
          if (movies.isEmpty && searchQuery.trim().isNotEmpty) {
            return _noSearchMatches();
          }
          if (movies.isEmpty) {
            return Center(
              child: EmptyState(
                title: 'Nothing queued',
                message:
                    'Pin films to priority or add them to “Movies in cinema” in the Library.',
                icon: Icons.push_pin_outlined,
              ),
            );
          }
          return maybeBrowseMore(
            context,
            scope: scope,
            itemCount: movies.length,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: NextToWatchPosterCard.gridChildAspectRatio,
              ),
              itemCount: movies.length,
              itemBuilder: (context, i) {
                return NextToWatchPosterCard(
                  item: movies[i],
                  username: username,
                  inGrid: true,
                  onTap: () => context.push(catalogItemDetailPath(movies[i].media)),
                );
              },
            ),
          );
        },
      );
    }

    if (key == 'games:events') {
      final async = ref.watch(stashGameEventsProvider(StashEventsWindow.previous));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e),
        data: (data) {
          var events = data.items;
          if (searchQuery.trim().isNotEmpty) {
            events = events.where(_matchesEvent).toList();
          }
          if (events.isEmpty && searchQuery.trim().isNotEmpty) {
            return _noSearchMatches();
          }
          if (events.isEmpty) {
            return Center(
              child: EmptyState(
                title: 'No past events',
                message: 'There are no industry events to show right now.',
                icon: Icons.event_busy_outlined,
              ),
            );
          }
          return StashEventsShelfList(events: events, onEventTap: (event) => context.push('/games/events/${event.slug}'));
        },
      );
    }

    if (key == 'movies:upcoming') {
      final async = ref.watch(movieHomeShelvesProvider);
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e),
        data: (home) {
          var items =
              home.upcoming.items.where(catalogItemIsUpcomingRelease).toList();
          if (searchQuery.trim().isNotEmpty) {
            items = items.where(_matches).toList();
          }
          if (items.isEmpty && searchQuery.trim().isNotEmpty) {
            return _noSearchMatches();
          }
          if (items.isEmpty) {
            return Center(
              child: EmptyState(
                title: 'No upcoming releases',
                message: 'There are no future theatrical dates in the catalog slice yet.',
                icon: Icons.upcoming_outlined,
              ),
            );
          }
          return maybeBrowseMore(
            context,
            scope: scope,
            itemCount: items.length,
            child: UpcomingShelfList(
              initialItems: items,
              paginateMovies: true,
              onItemTap: (item) => context.push(catalogItemDetailPath(item)),
            ),
          );
        },
      );
    }

    return const SizedBox.shrink();
  }
}
