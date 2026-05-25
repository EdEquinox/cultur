import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/core/storage_keys.dart';
import 'package:yamtrack/src/models/catalog/catalog_category.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/catalog_browse_providers.dart';
import 'package:yamtrack/src/providers/catalog_shelf_providers.dart';
import 'package:yamtrack/src/providers/catalog_tracking_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/search_provider.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/library/widgets/library_search_filter_header.dart';
import 'package:yamtrack/src/screens/media/movies/home/movie_catalog_filter_options.dart';
import 'package:yamtrack/src/screens/media/movies/home/widgets/movie_results_layout.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/screens/widgets/action_sheet_button.dart';
import 'package:yamtrack/src/screens/widgets/movie_poster_thumb.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/home_categories.dart';

class MoviesPage extends ConsumerStatefulWidget {
  const MoviesPage({
    this.initialQuery = '',
    this.initialGenre = '',
    this.initialKeyword = '',
    this.initialSection = '',
    super.key,
  });

  final String initialQuery;
  final String initialGenre;
  final String initialKeyword;
  final String initialSection;

  @override
  ConsumerState<MoviesPage> createState() => _MoviesPageState();
}

class _MoviesPageState extends ConsumerState<MoviesPage> {
  late final TextEditingController _queryController;
  late String _submittedQuery;
  late String _submittedGenre;
  late String _submittedKeyword;
  late String _submittedSection;
  final Set<String> _savingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _submittedQuery = widget.initialQuery.trim();
    _submittedGenre = widget.initialGenre.trim();
    _submittedKeyword = widget.initialKeyword.trim();
    _submittedSection = normalizedCatalogSection(
      CatalogBrowseKind.movies,
      widget.initialSection.trim(),
    );
    _queryController = TextEditingController(text: _submittedQuery);
    Future.microtask(_loadSearchSettings);
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _submitSearch() {
    setState(() {
      _submittedQuery = _queryController.text.trim();
    });
  }

  bool get _hasActiveFilters =>
      _submittedGenre.isNotEmpty ||
      _submittedKeyword.isNotEmpty ||
      _submittedSection != 'popular';

  void _clearFilters() {
    setState(() {
      _submittedGenre = '';
      _submittedKeyword = '';
      _submittedSection = 'popular';
    });
  }

  String _resultsHeading({int? resultCount}) {
    if (_submittedKeyword.isNotEmpty) {
      return 'Tag: $_submittedKeyword';
    }
    if (_submittedGenre.isNotEmpty) {
      return 'Genre: $_submittedGenre';
    }
    if (_submittedQuery.isNotEmpty) {
      return 'Results for "$_submittedQuery"';
    }
    final countSuffix = resultCount != null ? ' · $resultCount movies' : '';
    return switch (_submittedSection) {
      'now_playing' => 'Now playing$countSuffix',
      'upcoming' => 'Upcoming$countSuffix',
      'top_rated' => 'Top rated$countSuffix',
      _ => 'Popular on TMDB$countSuffix',
    };
  }

  String _emptyMessage() {
    if (_submittedKeyword.isNotEmpty) {
      return 'No movies matched this tag. Try another keyword.';
    }
    if (_submittedGenre.isNotEmpty) {
      return 'No movies matched this genre.';
    }
    if (_submittedQuery.isNotEmpty) {
      return 'There are no movies for this search yet. Try another title.';
    }
    if (_hasActiveFilters) {
      return 'No movies matched these filters. Try adjusting or clearing them.';
    }
    return 'Nothing to show right now.';
  }

  Future<void> _loadSearchSettings() async {
    final storage = ref.read(sessionStorageProvider);
    final columnsRaw = await storage.read(key: StorageKeys.movieSearchGridColumns);
    final viewRaw = await storage.read(key: StorageKeys.movieSearchViewMode);
    if (!mounted) {
      return;
    }
    final parsedColumns = int.tryParse(columnsRaw ?? '');
    if (parsedColumns != null) {
      ref.read(movieSearchGridColumnsProvider.notifier).state = parsedColumns.clamp(2, 4);
    }
    final parsedView = parseMovieSearchViewMode(viewRaw);
    if (parsedView != null) {
      ref.read(movieSearchViewModeProvider.notifier).state = parsedView;
    }
  }

  Future<void> _persistViewMode(MovieSearchViewMode mode) async {
    ref.read(movieSearchViewModeProvider.notifier).state = mode;
    await ref.read(sessionStorageProvider).write(
          key: StorageKeys.movieSearchViewMode,
          value: mode.name,
        );
  }

  Future<void> _refreshResults(CatalogBrowseRequest request, String? username) async {
    final tasks = <Future<Object?>>[ref.refresh(moviesProvider(request).future)];
    if (username != null && username.isNotEmpty) {
      tasks.add(ref.refresh(movieSearchTrackingProvider(username).future));
    }
    await Future.wait(tasks);
  }

  void _showSessionRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You need an active session to update your library.'),
      ),
    );
  }

  Future<void> _runTrackingMutation({
    required String username,
    required String savingId,
    required Future<String> Function(TrackingMutationController controller) mutation,
  }) async {
    setState(() => _savingIds.add(savingId));
    try {
      final successMessage = await mutation(ref.read(trackingMutationControllerProvider));
      ref.invalidate(movieSearchTrackingProvider(username));
      ref.invalidate(movieHomeShelvesProvider);
      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.movie));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      showApiErrorSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() => _savingIds.remove(savingId));
      }
    }
  }

  Future<void> _showWatchedSheet(
    CatalogItem item,
    TrackingItem? tracking,
    String username,
  ) async {
    final isWatched = trackingIsWatched(tracking);
    final shouldApply = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isWatched ? 'Update watched status' : 'Mark as watched',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                isWatched
                    ? 'Remove it from your watched list or keep it as completed.'
                    : 'This will move the movie out of your watchlist and into watched.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: Icon(
                        isWatched
                            ? Icons.visibility_off_outlined
                            : Icons.remove_red_eye_outlined,
                      ),
                      label: Text(isWatched ? 'Remove watched' : 'Mark watched'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (shouldApply != true) {
      return;
    }
    await _runTrackingMutation(
      username: username,
      savingId: item.id,
      mutation: (controller) => controller.toggleWatched(
        username: username,
        media: item,
        tracking: tracking,
      ),
    );
  }

  Future<void> _showActionsSheet(
    CatalogItem item,
    TrackingItem? tracking,
    String? username,
  ) async {
    final theme = Theme.of(context);
    final yearLabel = catalogItemReleaseDate(item)?.year.toString() ?? '';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MoviePosterThumb(
                    imageUrl: item.imageUrl,
                    width: 42,
                    height: 60,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (yearLabel.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(yearLabel, style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ActionSheetButton(
                      icon: trackingIsInWatchlist(tracking)
                          ? Icons.bookmark
                          : Icons.bookmark_border_outlined,
                      label: 'Watchlist',
                      active: trackingIsInWatchlist(tracking),
                      onTap: () {
                        Navigator.of(context).pop();
                        if (username == null || username.isEmpty) {
                          _showSessionRequiredMessage();
                          return;
                        }
                        _runTrackingMutation(
                          username: username,
                          savingId: item.id,
                          mutation: (c) => c.toggleWatchlist(
                            username: username,
                            media: item,
                            tracking: tracking,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ActionSheetButton(
                      icon: trackingIsWatched(tracking)
                          ? Icons.remove_red_eye
                          : Icons.remove_red_eye_outlined,
                      label: 'Watched',
                      active: trackingIsWatched(tracking),
                      onTap: () {
                        Navigator.of(context).pop();
                        if (username == null || username.isEmpty) {
                          _showSessionRequiredMessage();
                          return;
                        }
                        _showWatchedSheet(item, tracking, username);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/movies/${item.id}');
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View movie details'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _resultsHeader(BuildContext context, MovieSearchViewMode viewMode, {int? resultCount}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _resultsHeading(resultCount: resultCount),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        PopupMenuButton<MovieSearchViewMode>(
          tooltip: 'Change layout',
          icon: Icon(viewMode.icon),
          onSelected: _persistViewMode,
          itemBuilder: (context) => [
            for (final mode in MovieSearchViewMode.values)
              PopupMenuItem<MovieSearchViewMode>(
                value: mode,
                child: Row(
                  children: [
                    Icon(mode.icon, size: 18),
                    const SizedBox(width: 10),
                    Text(mode.label),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    final trackingByMediaId = username == null || username.isEmpty
        ? const <String, TrackingItem>{}
        : (ref.watch(movieSearchTrackingProvider(username)).asData?.value ??
            const <String, TrackingItem>{});
    final gridColumns = switch (ref.watch(movieSearchGridColumnsProvider)) {
      4 => 4,
      2 => 2,
      _ => 3,
    };
    final request = CatalogBrowseRequest(
      section: _submittedSection,
      query: _submittedQuery,
      genre: _submittedGenre,
      keyword: _submittedKeyword,
    );
    final movies = ref.watch(moviesProvider(request));
    final viewMode = ref.watch(movieSearchViewModeProvider);

    final filterOptions = buildMovieCatalogFilterOptions(
      section: _submittedSection,
      genre: _submittedGenre,
      onSectionChanged: (next) => setState(() => _submittedSection = next),
      onGenreChanged: (next) => setState(() => _submittedGenre = next),
    );

    return Scaffold(
      extendBody: true,
      appBar: const CulturAppBar(),
      body: RefreshIndicator(
        onRefresh: () => _refreshResults(request, username),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
          children: [
            LibrarySearchFilterHeader(
              searchController: _queryController,
              searchHint: 'The Matrix, Dune, Interstellar...',
              onSearchChanged: (_) => setState(() {}),
              onSearchSubmitted: (_) => _submitSearch(),
              filterOptions: filterOptions,
              onClearAll: _hasActiveFilters ? _clearFilters : null,
              padding: EdgeInsets.zero,
              searchTrailing: IconButton(
                tooltip: 'Search',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                onPressed: _submitSearch,
                icon: const Icon(Icons.search, size: 18),
              ),
            ),
            const SizedBox(height: 16),
            movies.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => ErrorState(
                error: error,
                onRetry: () => ref.invalidate(moviesProvider(request)),
              ),
              data: (data) {
                if (data.items.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _resultsHeader(context, viewMode, resultCount: 0),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 280,
                        child: EmptyState(
                          title: 'No movies',
                          message: _emptyMessage(),
                          icon: Icons.movie_outlined,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _resultsHeader(context, viewMode, resultCount: data.items.length),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: MovieResultsLayout(
                        key: ValueKey(viewMode),
                        viewMode: viewMode,
                        items: data.items,
                        gridColumns: gridColumns,
                        onOpenMovie: (item) => context.push('/movies/${item.id}'),
                        onOpenActions: (item) =>
                            _showActionsSheet(item, trackingByMediaId[item.id], username),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: const FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: LibraryMediaScope.movie,
      ),
    );
  }
}
