import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/albums_home_providers.dart';
import 'package:yamtrack/src/screens/home/widgets/category_home_manual_create_bar.dart';
import 'package:yamtrack/src/screens/home/widgets/pending_imports_home_section.dart';
import 'package:yamtrack/src/screens/home/widgets/latest_release_section.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/games_tracking_shelf_section.dart';
import 'package:yamtrack/src/screens/home/widgets/collected_lent_home_section.dart';
import 'package:yamtrack/src/utils/library_utils.dart';

class AlbumsCategoryHomeBody extends ConsumerWidget {
  const AlbumsCategoryHomeBody({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextToListen = ref.watch(albumsNextToListenShelfProvider(username));
    final latestAlbums = ref.watch(albumsMusicLatestProvider(username));

    return Column(
      children: [
        PendingImportsHomeSection(
          username: username,
          scope: LibraryMediaScope.music,
          emptyMessage:
              'Albums that could not be matched during import appear here. Open one and link it from the album page.',
          onSeeAll: () => context.push(
            '${LibraryMediaScope.music.libraryBasePath}/lists/${BuiltInMusicLists.pendingImportsListId}',
          ),
        ),
        GamesTrackingShelfSection(
          title: 'Next to listen',
          icon: Icons.headphones_outlined,
          state: nextToListen,
          emptyMessage:
              'Add albums to Later or mark them as priority — they show up here.',
          onSeeAll: () => context.push(
            LibraryMediaScope.music.path('later'),
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
          title: 'Latest ratings',
          icon: Icons.grade_outlined,
          state: latestAlbums.when(
            data: (items) => AsyncData(CatalogListData(items: items)),
            loading: () => const AsyncLoading(),
            error: (error, stackTrace) => AsyncError(error, stackTrace),
          ),
          emptyMessage: 'Albums you rate will appear here, newest first.',
          onSeeAll: () => context.push(LibraryMediaScope.music.libraryBasePath),
        ),
        const CollectedLentHomeSection(mediaScope: LibraryMediaScope.music),
        CategoryHomeManualCreateBar(
          scope: LibraryMediaScope.music,
          username: username,
        ),
      ],
    );
  }
}
