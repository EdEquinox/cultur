import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/books_home_providers.dart';
import 'package:yamtrack/src/screens/home/widgets/category_home_manual_create_bar.dart';
import 'package:yamtrack/src/screens/home/widgets/pending_imports_home_section.dart';
import 'package:yamtrack/src/utils/library_utils.dart';
import 'package:yamtrack/src/screens/home/widgets/latest_release_section.dart';
import 'package:yamtrack/src/screens/media/books/home/widgets/books_reading_shelf_section.dart';
import 'package:yamtrack/src/screens/home/widgets/collected_lent_home_section.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/games_tracking_shelf_section.dart';

class BooksCategoryHomeBody extends ConsumerWidget {
  const BooksCategoryHomeBody({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(booksReadingShelfProvider(username));
    final nextToRead = ref.watch(booksNextToReadShelfProvider(username));
    final popular = ref.watch(booksPopularProvider);

    return Column(
      children: [
        PendingImportsHomeSection(
          username: username,
          scope: LibraryMediaScope.book,
          emptyMessage:
              'Books that could not be matched during Bookmory import appear here. Open one and use Search catalog to link it.',
          onSeeAll: () => context.push(
            '${LibraryMediaScope.book.libraryBasePath}/lists/${BuiltInBookLists.pendingImportsListId}',
          ),
        ),
        BooksReadingShelfSection(
          title: 'Reading',
          state: reading,
          username: username,
          emptyMessage:
              'Mark books as Reading from a book page — update pages here as you go.',
          onSeeAll: () => context.push(
            LibraryMediaScope.book.path('doing'),
          ),
        ),
        const SizedBox(height: 16),
        GamesTrackingShelfSection(
          title: 'Next to read',
          icon: Icons.bookmark_added_outlined,
          state: nextToRead,
          emptyMessage:
              'Add books to Later or mark them as priority — they show up here.',
          onSeeAll: () => context.push(
            LibraryMediaScope.book.path('later'),
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
          title: 'Popular',
          icon: Icons.trending_up_outlined,
          state: popular,
          emptyMessage: 'Could not load popular books.',
          onSeeAll: () => context.push('/category/books'),
        ),
        const CollectedLentHomeSection(mediaScope: LibraryMediaScope.book),
        CategoryHomeManualCreateBar(
          scope: LibraryMediaScope.book,
          username: username,
        ),
      ],
    );
  }
}
