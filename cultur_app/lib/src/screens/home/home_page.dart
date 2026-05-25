import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/catalog/catalog_category.dart';
import 'package:yamtrack/src/models/auth/auth_session.dart';
import 'package:yamtrack/src/screens/home/widgets/home_header_rail.dart';
import 'package:yamtrack/src/screens/home/widgets/home_body.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/utils/home_categories.dart';
import 'package:yamtrack/src/providers/catalog_shelf_providers.dart';
import 'package:yamtrack/src/providers/catalog_tracking_providers.dart';
import 'package:yamtrack/src/providers/boardgames_home_providers.dart';
import 'package:yamtrack/src/providers/albums_home_providers.dart';
import 'package:yamtrack/src/providers/books_home_providers.dart';
import 'package:yamtrack/src/providers/games_home_providers.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({
    required this.session,
    super.key,
  });

  final AuthSession session;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final TextEditingController _searchController;
  String _selectedCategoryId = catalogCategories.first.id;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshCurrentCategory() {
    switch (_selectedCategoryId) {
      case 'movies':
        return Future.wait([
          ref.refresh(movieSearchTrackingProvider(widget.session.username).future),
          ref.refresh(customMovieListsProvider.future),
          ref.refresh(movieHomeShelvesProvider.future),
        ]);
      case 'series':
        return Future.wait([
          ref.refresh(tvHomeShelvesProvider(widget.session.username).future),
          ref.refresh(tvSearchTrackingProvider(widget.session.username).future),
          ref.refresh(customMovieListsProvider.future),
        ]);
      case 'games':
        invalidateGamesHomeCaches(ref, username: widget.session.username);
        return Future.wait([
          ref.refresh(gamesPlayingShelfProvider(widget.session.username).future),
          ref.refresh(gamesNextToPlayShelfProvider(widget.session.username).future),
          ref.refresh(stashGameEventsProvider(StashEventsWindow.upcoming).future),
          ref.refresh(stashGameEventsProvider(StashEventsWindow.previous).future),
        ]);
      case 'books':
        invalidateBooksHomeCaches(ref, username: widget.session.username);
        return Future.wait([
          ref.refresh(booksPopularProvider.future),
          ref.refresh(booksReadingShelfProvider(widget.session.username).future),
          ref.refresh(booksNextToReadShelfProvider(widget.session.username).future),
        ]);
      case 'albums':
        invalidateAlbumsHomeCaches(ref, username: widget.session.username);
        return Future.wait([
          ref.refresh(albumsMusicLatestProvider(widget.session.username).future),
          ref.refresh(albumsNextToListenShelfProvider(widget.session.username).future),
        ]);
      case 'board-games':
        invalidateBoardgamesHomeCaches(ref, username: widget.session.username);
        return Future.wait([
          ref.refresh(boardgamesPopularProvider.future),
          ref.refresh(boardgamesNextToTryShelfProvider(widget.session.username).future),
        ]);
      default:
        return Future.value();
    }
  }

  void _submitSearch(AppCategory category) {
    final query = _searchController.text.trim();
    final target = query.isEmpty
        ? '/category/${category.id}'
        : '/category/${category.id}?q=${Uri.encodeQueryComponent(query)}';
    context.push(target);
  }

  String _searchHint(AppCategory category) {
    switch (category.id) {
      case 'movies':
        return 'Search movies, directors, franchises...';
      case 'series':
        return 'Search series, seasons, universes...';
      case 'games':
        return 'Search games and franchises...';
      case 'books':
        return 'Search books and authors...';
      case 'albums':
        return 'Search albums and artists...';
      case 'board-games':
        return 'Search board games and designers...';
      default:
        return 'Search';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uriCategory = GoRouterState.of(context).uri.queryParameters['category'];
    if (uriCategory != null) {
      final cat = catalogCategoryById(uriCategory);
      if (cat != null && cat.id != _selectedCategoryId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _selectedCategoryId = cat.id);
          }
        });
      }
    }

    final currentCategory =
        catalogCategoryById(_selectedCategoryId) ?? catalogCategories.first;
    final libraryNavScope = switch (_selectedCategoryId) {
      'series' => LibraryMediaScope.tv,
      'games' => LibraryMediaScope.game,
      'books' => LibraryMediaScope.book,
      'albums' => LibraryMediaScope.music,
      'board-games' => LibraryMediaScope.boardgame,
      _ => LibraryMediaScope.movie,
    };

    return Scaffold(
      extendBody: true,
      appBar: const CulturAppBar(),
      body: RefreshIndicator(
        onRefresh: _refreshCurrentCategory,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 132),
          children: [
            HomeHeaderRail(
              categories: catalogCategories,
              selectedCategoryId: currentCategory.id,
              onSelected: (categoryId) {
                setState(() {
                  _selectedCategoryId = categoryId;
                });
                context.go('/?category=${Uri.encodeComponent(categoryId)}');
              },
            ),
            const SizedBox(height: 12),
            LibraryItemSearchField(
              controller: _searchController,
              hintText: _searchHint(currentCategory),
              registerForPageSearchFab: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submitSearch(currentCategory),
              trailing: IconButton(
                tooltip: 'Open category',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                onPressed: () => _submitSearch(currentCategory),
                icon: const Icon(Icons.arrow_forward, size: 18),
              ),
            ),
            const SizedBox(height: 20),
            HomeBody(
              category: currentCategory,
              username: widget.session.username,
            ),
          ],
        ),
      ),
      bottomNavigationBar: FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: libraryNavScope,
      ),
    );
  }
}
