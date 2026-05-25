import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/core/storage_keys.dart';
import 'package:yamtrack/src/models/catalog/catalog_category.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/catalog_browse_providers.dart';
import 'package:yamtrack/src/providers/game_search_view_provider.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/game_results_layout.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/home_categories.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_metrics.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';

class AlbumsPage extends ConsumerStatefulWidget {
  const AlbumsPage({
    this.initialQuery = '',
    this.initialSection = '',
    super.key,
  });

  final String initialQuery;
  final String initialSection;

  @override
  ConsumerState<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends ConsumerState<AlbumsPage> {
  late final TextEditingController _queryController;
  late String _submittedQuery;

  @override
  void initState() {
    super.initState();
    _submittedQuery = widget.initialQuery.trim();
    _queryController = TextEditingController(text: _submittedQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadSearchSettings();
      }
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadSearchSettings() async {
    if (!mounted) {
      return;
    }
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
    if (!mounted) {
      return;
    }
    ref.read(gameSearchViewModeProvider.notifier).state = mode;
    await ref.read(sessionStorageProvider).write(
          key: StorageKeys.gameSearchViewMode,
          value: mode.name,
        );
  }

  void _submitSearch() {
    setState(() => _submittedQuery = _queryController.text.trim());
  }

  String get _section =>
      normalizedCatalogSection(CatalogBrowseKind.albums, widget.initialSection);

  bool get _isPopularBrowse => _section == 'popular' || _section == 'trending';

  CatalogBrowseRequest get _browseRequest => CatalogBrowseRequest(
        section: _isPopularBrowse ? _section : 'search',
        query: _isPopularBrowse ? '' : _submittedQuery,
      );

  String _resultsHeading({int? resultCount}) {
    if (_isPopularBrowse) {
      final countSuffix = resultCount != null ? ' · $resultCount albums' : '';
      return 'Popular this week$countSuffix';
    }
    if (_submittedQuery.isEmpty) {
      return 'Search albums';
    }
    final countSuffix = resultCount != null ? ' · $resultCount albums' : '';
    return 'Results for "$_submittedQuery"$countSuffix';
  }

  Widget _resultsHeader(BuildContext context, GameSearchViewMode viewMode, {int? resultCount}) {
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

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(albumsCatalogProvider(_browseRequest));
    final viewMode = ref.watch(gameSearchViewModeProvider);
    final gridColumns = switch (ref.watch(gameSearchGridColumnsProvider)) {
      3 => 3,
      4 => 4,
      _ => 2,
    };

    return Scaffold(
      extendBody: true,
      appBar: const CulturAppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          if (!mounted) {
            return;
          }
          ref.invalidate(albumsCatalogProvider(_browseRequest));
          await ref.read(albumsCatalogProvider(_browseRequest).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
          children: [
            LibraryItemSearchField(
              controller: _queryController,
              hintText: 'Bo Burnham, Inside, artist or album…',
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
            ),
            const SizedBox(height: 16),
            results.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => ErrorState(
                error: error,
                onRetry: () => ref.invalidate(albumsCatalogProvider(_browseRequest)),
              ),
              data: (data) {
                if (!_isPopularBrowse && _submittedQuery.isEmpty) {
                  return const SizedBox(
                    height: 280,
                    child: EmptyState(
                      title: 'Search albums',
                      message:
                          'Enter an artist or album — search uses Last.fm only.',
                      icon: Icons.search_outlined,
                    ),
                  );
                }
                if (data.items.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _resultsHeader(context, viewMode, resultCount: 0),
                      const SizedBox(height: 12),
                      const SizedBox(
                        height: 280,
                        child: EmptyState(
                          title: 'No results',
                          message: 'Try another search term.',
                          icon: Icons.album_outlined,
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
                        gridChildAspectRatio: CulturCatalogGridMetrics.musicGridChildAspectRatio,
                        onOpenGame: (CatalogItem item) =>
                            context.push(catalogItemDetailPath(item)),
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
        currentDestination: null,
        mediaScope: LibraryMediaScope.music,
      ),
    );
  }
}
