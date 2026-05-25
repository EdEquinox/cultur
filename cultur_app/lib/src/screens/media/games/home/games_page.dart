import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/core/storage_keys.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/catalog_browse_providers.dart';
import 'package:yamtrack/src/providers/catalog_tracking_providers.dart';
import 'package:yamtrack/src/providers/game_search_view_provider.dart';
import 'package:yamtrack/src/providers/games_home_providers.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/providers/game_catalog_filters_provider.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';
import 'package:yamtrack/src/screens/library/widgets/library_filter_option.dart';
import 'package:yamtrack/src/screens/library/widgets/library_search_filter_header.dart';
import 'package:yamtrack/src/screens/media/games/home/game_catalog_filter_options.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/screens/widgets/action_sheet_button.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/game_results_layout.dart';
import 'package:yamtrack/src/screens/widgets/movie_poster_thumb.dart';
import 'package:yamtrack/src/models/catalog/catalog_category.dart';
import 'package:yamtrack/src/utils/home_categories.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';

class GamesPage extends ConsumerStatefulWidget {
  const GamesPage({
    this.initialQuery = '',
    this.initialSection = '',
    this.initialCompanyId = '',
    this.initialCompanyRole = '',
    this.initialCompanyName = '',
    this.initialFranchiseId = '',
    this.initialCollectionId = '',
    this.initialBrowseName = '',
    super.key,
  });

  final String initialQuery;
  final String initialSection;
  final String initialCompanyId;
  final String initialCompanyRole;
  final String initialCompanyName;
  final String initialFranchiseId;
  final String initialCollectionId;
  final String initialBrowseName;

  @override
  ConsumerState<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends ConsumerState<GamesPage> {
  late final TextEditingController _queryController;
  late String _submittedQuery;
  late String _submittedSection;
  late String _companyId;
  late String _companyRole;
  late String _companyName;
  late String _franchiseId;
  late String _collectionId;
  late String _browseName;
  Set<String> _platformIds = {};
  Set<String> _genreIds = {};
  Set<String> _gameModeIds = {};
  Set<String> _playerPerspectiveIds = {};
  String _gameTypeId = '';
  final Set<String> _savingIds = <String>{};

  bool get _scopedBrowse =>
      _companyId.isNotEmpty || _franchiseId.isNotEmpty || _collectionId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _submittedQuery = widget.initialQuery.trim();
    _submittedSection = widget.initialCompanyId.isNotEmpty ||
            widget.initialFranchiseId.isNotEmpty ||
            widget.initialCollectionId.isNotEmpty
        ? 'popular'
        : normalizedCatalogSection(
            CatalogBrowseKind.games,
            widget.initialSection.trim(),
          );
    _companyId = widget.initialCompanyId.trim();
    _companyRole = widget.initialCompanyRole.trim();
    _companyName = widget.initialCompanyName.trim();
    _franchiseId = widget.initialFranchiseId.trim();
    _collectionId = widget.initialCollectionId.trim();
    _browseName = widget.initialBrowseName.trim();
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
      _submittedSection = 'popular';
    });
  }

  String _resultsHeading({int? resultCount}) {
    if (_franchiseId.isNotEmpty) {
      final label = _browseName.isNotEmpty ? _browseName : 'Game series';
      final countSuffix = resultCount != null ? ' · $resultCount games' : '';
      return '$label$countSuffix';
    }
    if (_collectionId.isNotEmpty) {
      final label = _browseName.isNotEmpty ? _browseName : 'Bundle';
      final countSuffix = resultCount != null ? ' · $resultCount games' : '';
      return '$label$countSuffix';
    }
    if (_companyId.isNotEmpty) {
      final label = _companyName.isNotEmpty ? _companyName : 'Company';
      final role = _companyRole == 'developer' ? 'developer' : 'publisher';
      final countSuffix = resultCount != null ? ' · $resultCount games' : '';
      return 'Games from $label ($role)$countSuffix';
    }
    if (_submittedQuery.isNotEmpty) {
      return 'Results for "$_submittedQuery"';
    }
    return switch (_submittedSection) {
      'top_rated' => 'Top rated on IGDB',
      'upcoming' => 'Upcoming releases',
      'recent' => 'Recently released',
      _ => 'Popular on IGDB',
    };
  }

  Widget _resultsHeader(
    BuildContext context,
    GameSearchViewMode viewMode, {
    int? resultCount,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _resultsHeading(resultCount: resultCount),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        PopupMenuButton<GameSearchViewMode>(
          tooltip: 'Change layout',
          icon: Icon(viewMode.icon),
          onSelected: _persistViewMode,
          itemBuilder: (context) => [
            for (final mode in GameSearchViewMode.values)
              PopupMenuItem<GameSearchViewMode>(
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

  String _emptyMessage() {
    if (_franchiseId.isNotEmpty) {
      return 'No other games found in this series on IGDB.';
    }
    if (_collectionId.isNotEmpty) {
      return 'No games found in this bundle on IGDB.';
    }
    if (_companyId.isNotEmpty) {
      return 'No games found for this company on IGDB.';
    }
    if (_submittedQuery.isNotEmpty) {
      return 'No games matched this search. Try another title.';
    }
    if (_hasActiveIgdbFilters) {
      return 'No games matched these filters. Try adjusting or clearing them.';
    }
    return 'Nothing to show right now.';
  }

  bool get _hasActiveIgdbFilters =>
      _platformIds.isNotEmpty ||
      _genreIds.isNotEmpty ||
      _gameModeIds.isNotEmpty ||
      _playerPerspectiveIds.isNotEmpty ||
      _gameTypeId.isNotEmpty;

  Future<void> _loadSearchSettings() async {
    final storage = ref.read(sessionStorageProvider);
    final columnsRaw = await storage.read(key: StorageKeys.movieSearchGridColumns);
    final viewRaw = await storage.read(key: StorageKeys.gameSearchViewMode);
    if (!mounted) {
      return;
    }
    final parsedColumns = int.tryParse(columnsRaw ?? '');
    if (parsedColumns != null) {
      ref.read(gameSearchGridColumnsProvider.notifier).state = parsedColumns.clamp(2, 4);
    }
    final parsedView = parseGameSearchViewMode(viewRaw);
    if (parsedView != null) {
      ref.read(gameSearchViewModeProvider.notifier).state = parsedView;
    }
  }

  Future<void> _persistViewMode(GameSearchViewMode mode) async {
    ref.read(gameSearchViewModeProvider.notifier).state = mode;
    await ref.read(sessionStorageProvider).write(
          key: StorageKeys.gameSearchViewMode,
          value: mode.name,
        );
  }

  Future<void> _refreshResults(CatalogBrowseRequest request, String? username) async {
    final tasks = <Future<Object?>>[ref.refresh(gamesProvider(request).future)];
    if (username != null && username.isNotEmpty) {
      tasks.add(ref.refresh(gameSearchTrackingProvider(username).future));
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
      ref.invalidate(gameSearchTrackingProvider(username));
      invalidateGamesHomeCaches(ref, username: username);
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
                isWatched ? 'Update finished status' : 'Mark as finished',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                isWatched
                    ? 'Remove this game from your finished list.'
                    : 'Mark the game as completed (Stash: Beaten).',
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
                        isWatched ? Icons.check_circle : Icons.check_circle_outline,
                      ),
                      label: Text(isWatched ? 'Remove finished' : 'Mark finished'),
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
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
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
                      label: 'Later',
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
                      icon: trackingIsInWatchingCollection(tracking)
                          ? Icons.play_circle
                          : Icons.play_circle_outline,
                      label: 'Playing',
                      active: trackingIsInWatchingCollection(tracking),
                      onTap: () {
                        Navigator.of(context).pop();
                        if (username == null || username.isEmpty) {
                          _showSessionRequiredMessage();
                          return;
                        }
                        _runTrackingMutation(
                          username: username,
                          savingId: item.id,
                          mutation: (c) => c.toggleDoing(
                            username: username,
                            media: item,
                            tracking: tracking,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ActionSheetButton(
                      icon: trackingIsWatched(tracking)
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                      label: 'Finished',
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
                    context.push('/games/${item.id}');
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View game details'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    final trackingByMediaId = username == null || username.isEmpty
        ? const <String, TrackingItem>{}
        : (ref.watch(gameSearchTrackingProvider(username)).asData?.value ??
            const <String, TrackingItem>{});
    final gridColumns = switch (ref.watch(gameSearchGridColumnsProvider)) {
      3 => 3,
      4 => 4,
      _ => 2,
    };
    final request = CatalogBrowseRequest(
      section: _submittedSection,
      query: _submittedQuery,
      companyId: _companyId,
      companyRole: _companyRole.isNotEmpty ? _companyRole : 'publisher',
      franchiseId: _franchiseId,
      collectionId: _collectionId,
      platform: _platformIds.join(','),
      igdbGenre: _genreIds.join(','),
      gameMode: _gameModeIds.join(','),
      playerPerspective: _playerPerspectiveIds.join(','),
      gameType: _gameTypeId,
    );
    final games = ref.watch(gamesProvider(request));
    final viewMode = ref.watch(gameSearchViewModeProvider);
    final catalogFilters = ref.watch(gameCatalogFiltersProvider);

    void clearIgdbFilters() {
      setState(() {
        _platformIds = {};
        _genreIds = {};
        _gameModeIds = {};
        _playerPerspectiveIds = {};
        _gameTypeId = '';
      });
    }

    Widget searchHeader() {
      if (_scopedBrowse) {
        return LibraryItemSearchField(
          controller: _queryController,
          hintText: 'Cyberpunk 2077, Elden Ring, Hades...',
          registerForPageSearchFab: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submitSearch(),
          trailing: IconButton(
            tooltip: 'Search',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            onPressed: _submitSearch,
            icon: const Icon(Icons.search, size: 18),
          ),
        );
      }

      final filterOptions = catalogFilters.maybeWhen(
        data: (filters) => buildGameCatalogFilterOptions(
          filters: filters,
          platformIds: _platformIds,
          genreIds: _genreIds,
          gameModeIds: _gameModeIds,
          playerPerspectiveIds: _playerPerspectiveIds,
          gameTypeId: _gameTypeId,
          onPlatformsChanged: (next) => setState(() => _platformIds = next),
          onGenresChanged: (next) => setState(() => _genreIds = next),
          onGameModesChanged: (next) => setState(() => _gameModeIds = next),
          onPlayerPerspectivesChanged: (next) =>
              setState(() => _playerPerspectiveIds = next),
          onGameTypeChanged: (next) => setState(() => _gameTypeId = next),
        ),
        orElse: () => const <LibraryFilterOption>[],
      );

      return LibrarySearchFilterHeader(
        searchController: _queryController,
        searchHint: 'Cyberpunk 2077, Elden Ring, Hades...',
        onSearchChanged: (_) => setState(() {}),
        onSearchSubmitted: (_) => _submitSearch(),
        filterOptions: filterOptions,
        onClearAll: _hasActiveIgdbFilters ? clearIgdbFilters : null,
        padding: EdgeInsets.zero,
        searchTrailing: IconButton(
          tooltip: 'Search',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          onPressed: _submitSearch,
          icon: const Icon(Icons.search, size: 18),
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      appBar: const CulturAppBar(),
      body: RefreshIndicator(
        onRefresh: () => _refreshResults(request, username),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
          children: [
            searchHeader(),
            const SizedBox(height: 16),
            games.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => ErrorState(
                error: error,
                onRetry: () => ref.invalidate(gamesProvider(request)),
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
                          title: 'No games',
                          message: _emptyMessage(),
                          icon: Icons.sports_esports_outlined,
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
                      child: GameResultsLayout(
                        key: ValueKey(viewMode),
                        viewMode: viewMode,
                        items: data.items,
                        gridColumns: gridColumns,
                        onOpenGame: (item) => context.push('/games/${item.id}'),
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
        mediaScope: LibraryMediaScope.game,
      ),
    );
  }
}
