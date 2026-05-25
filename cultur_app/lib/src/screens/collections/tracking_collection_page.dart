import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/providers/catalog_shelf_providers.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/library/library_tracking_filter_model.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/models/library/watched_tv_episode_library_row.dart';
import 'package:yamtrack/src/providers/albums_home_providers.dart';
import 'package:yamtrack/src/providers/games_home_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/models/library/library_enums.dart';
import 'package:yamtrack/src/screens/library/library_view_mode_ui.dart';
import 'package:yamtrack/src/screens/library/widgets/library_actions_sheet_content.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';
import 'package:yamtrack/src/screens/library/widgets/library_search_filter_header.dart';
import 'package:yamtrack/src/screens/library/widgets/library_tracking_filter_options.dart';
import 'package:yamtrack/src/models/library/collected_ownership.dart';
import 'package:yamtrack/src/screens/collections/widgets/collected_catalog_poster_card.dart';
import 'package:yamtrack/src/screens/collections/widgets/collected_lent_dialog.dart';
import 'package:yamtrack/src/screens/library/widgets/finished_tracking_history_body.dart';
import 'package:yamtrack/src/screens/library/widgets/library_watched_style_catalog_row.dart';
import 'package:yamtrack/src/utils/library_item_search.dart';
import 'package:yamtrack/src/screens/library/widgets/tv_watched_history_body.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';
import 'package:yamtrack/src/utils/collected_toggle_flow.dart';
import 'package:yamtrack/src/utils/sorting.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
enum LibrarySortDirection {
  last,
  first,
}

enum TvWatchedLibraryViewMode {
  episodes,
  series,
}

enum LibraryTrackingSortKey {
  defaultOrder,
  markedWatched,
  markedOwned,
  markedDropped,
  watchHistoryEntries,
  ratingEdited,
  myRating,
  tmdbRating,
  addedToList,
  firstReleaseDate,
  title,
  runtime,
  newestEpisodeAirDate,
  episodeRuntime,
  numberOfSeasons,
  gross,
  budget,
}

class TrackingCollectionPage extends ConsumerStatefulWidget {
  const TrackingCollectionPage({
    required this.kind,
    required this.mediaScope,
    super.key,
  });

  final LibraryCollectionKind kind;
  final LibraryMediaScope mediaScope;

  @override
  ConsumerState<TrackingCollectionPage> createState() => _TrackingCollectionPageState();
}

class _TrackingCollectionPageState extends ConsumerState<TrackingCollectionPage> {
  LibraryViewMode _viewMode = LibraryViewMode.detailed;
  final Set<String> _savingIds = <String>{};
  final Set<String> _tvEpisodeUnwatchBusy = <String>{};
  final LibraryTrackingFilterModel _filterModel = LibraryTrackingFilterModel();
  LibraryTrackingSortKey _sortKey = LibraryTrackingSortKey.defaultOrder;
  LibrarySortDirection _sortDirection = LibrarySortDirection.last;
  TvWatchedLibraryViewMode _tvWatchedViewMode = TvWatchedLibraryViewMode.episodes;
  bool _tvSeriesProgressSynced = false;
  late final TextEditingController _searchController;

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

  String get _searchQuery => _searchController.text;

  List<TrackingItem> _sortedTrackingItems(List<TrackingItem> items) {
    final out = [...items];
    sortTrackingItemsInPlace(out, key: _sortKey, direction: _sortDirection);
    return out;
  }

  Future<void> _openSortSheet({required bool tvEpisodeSortContext}) async {
    await showLibraryTrackingSortSheet(
      context,
      mediaScope: widget.mediaScope,
      tvEpisodeSortContext: tvEpisodeSortContext,
      currentKey: _sortKey,
      currentDirection: _sortDirection,
      onApply: (k, d) => setState(() {
        _sortKey = k;
        _sortDirection = d;
      }),
    );
  }

  String tvEpisodeBusyKey(WatchedTvEpisodeLibraryRow row) =>
      '${row.media.id}-${row.seasonNumber}-${row.episodeNumber}';

  Future<void> unwatchTvEpisode(WatchedTvEpisodeLibraryRow row) async {
    final auth = ref.read(authControllerProvider).asData?.value;
    final username = auth?.session?.username;
    if (username == null || username.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to update watched episodes.')),
        );
      }
      return;
    }
    final key = tvEpisodeBusyKey(row);
    setState(() => _tvEpisodeUnwatchBusy.add(key));
    try {
      await ref.read(episodeWatchMutationControllerProvider).putEpisodeWatched(
            username: username,
            mediaId: row.media.id,
            seasonNumber: row.seasonNumber,
            episodeNumber: row.episodeNumber,
            watched: false,
          );
      invalidateTvEpisodeWatchCaches(ref, username: username);
      ref.invalidate(tvFullyWatchedSeriesLibraryProvider(username));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Episode marked as not watched.')),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      showApiErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _tvEpisodeUnwatchBusy.remove(key));
      }
    }
  }

  Future<void> runTrackingMutation({
    required TrackingItem item,
    required Future<String?> Function(TrackingMutationController controller) mutation,
  }) async {
    setState(() {
      _savingIds.add(item.id);
    });
    try {
      final successMessage = await mutation(
        ref.read(trackingMutationControllerProvider),
      );
      if (successMessage == null) {
        return;
      }
      ref.invalidate(libraryTrackingForScopeProvider(widget.mediaScope));
      if (widget.mediaScope == LibraryMediaScope.game) {
        final username = item.username.trim();
        if (username.isNotEmpty) {
          invalidateGamesHomeCaches(ref, username: username);
        }
        ref.invalidate(customGameListsProvider);
      }
      if (widget.mediaScope == LibraryMediaScope.music) {
        final username = item.username.trim();
        if (username.isNotEmpty) {
          invalidateAlbumsHomeCaches(ref, username: username);
        }
        ref.invalidate(customMusicListsProvider);
      }
      if (widget.kind == LibraryCollectionKind.finished &&
          widget.mediaScope == LibraryMediaScope.tv) {
        final username = item.username.trim();
        if (username.isNotEmpty) {
          ref.invalidate(tvFullyWatchedSeriesLibraryProvider(username));
          ref.invalidate(tvWatchedEpisodesLibraryProvider);
        }
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      showApiErrorSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _savingIds.remove(item.id);
        });
      }
    }
  }

  Future<void> showActionsSheet(TrackingItem item) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (context) {
        return LibraryActionsSheetContent(
          item: item,
          onCollectedTap: () {
            Navigator.of(context).pop();
            runTrackingMutation(
              item: item,
              mutation: (controller) => runCollectedToggle(
                context: context,
                controller: controller,
                username: item.username,
                media: item.media,
                tracking: item,
              ),
            );
          },
          onWatchlistTap: () {
            Navigator.of(context).pop();
            runTrackingMutation(
              item: item,
              mutation: (controller) => controller.toggleWatchlist(
                username: item.username,
                media: item.media,
                tracking: item,
              ),
            );
          },
          onWatchedTap: () {
            Navigator.of(context).pop();
            runTrackingMutation(
              item: item,
              mutation: (controller) => controller.toggleWatched(
                username: item.username,
                media: item.media,
                tracking: item,
              ),
            );
          },
          onDoingTap: () {
            Navigator.of(context).pop();
            runTrackingMutation(
              item: item,
              mutation: (controller) => controller.toggleDoing(
                username: item.username,
                media: item.media,
                tracking: item,
              ),
            );
          },
          onBuyTap: () {
            Navigator.of(context).pop();
            runTrackingMutation(
              item: item,
              mutation: (controller) => controller.toggleBuy(
                username: item.username,
                media: item.media,
                tracking: item,
              ),
            );
          },
          onLeftTap: () {
            Navigator.of(context).pop();
            runTrackingMutation(
              item: item,
              mutation: (controller) => controller.toggleDropped(
                username: item.username,
                media: item.media,
                tracking: item,
              ),
            );
          },
          onOpenMovie: () {
            Navigator.of(context).pop();
            final m = item.media;
            context.push(catalogItemDetailPath(m));
          },
          onPriorityTap: widget.mediaScope == LibraryMediaScope.game
              ? () {
                  Navigator.of(context).pop();
                  runTrackingMutation(
                    item: item,
                    mutation: (controller) => controller.togglePriority(
                          username: item.username,
                          media: item.media,
                          tracking: item,
                        ),
                  );
                }
              : null,
        );
      },
    );
  }

  Widget libraryListHeader({Widget? trailingAfterFilters}) {
    return LibrarySearchFilterHeader(
      searchController: _searchController,
      searchHint: 'Search in ${_title.toLowerCase()}…',
      onSearchChanged: (_) => setState(() {}),
      filterOptions: buildLibraryTrackingFilterOptions(
        context: context,
        surface: LibraryFilterSurface.tracking,
        trackingCollectionKind: widget.kind,
        mediaScope: widget.mediaScope,
        model: _filterModel,
        onModelChanged: (_) => setState(() {}),
      ),
      onClearAll: () {
        _filterModel.clearAll();
        setState(() {});
      },
      trailingAfterFilters: trailingAfterFilters,
    );
  }

  Widget? _tvWatchedViewToggle() {
    if (widget.kind != LibraryCollectionKind.finished ||
        widget.mediaScope != LibraryMediaScope.tv) {
      return null;
    }
    return SegmentedButton<TvWatchedLibraryViewMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: TvWatchedLibraryViewMode.episodes,
            tooltip: 'Episodes',
            icon: Icon(Icons.view_list_outlined, size: 20),
          ),
          ButtonSegment(
            value: TvWatchedLibraryViewMode.series,
            tooltip: 'Series',
            icon: Icon(Icons.tv_outlined, size: 20),
          ),
        ],
        selected: {_tvWatchedViewMode},
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(40, 36)),
          maximumSize: const WidgetStatePropertyAll(Size(48, 36)),
          iconSize: const WidgetStatePropertyAll(20),
        ),
        onSelectionChanged: (selection) {
          if (selection.isEmpty) {
            return;
          }
          final next = selection.first;
          setState(() => _tvWatchedViewMode = next);
          if (next == TvWatchedLibraryViewMode.series) {
            _scheduleTvSeriesProgressSync();
          }
        },
      );
  }

  Widget _tvWatchedListHeader() {
    return libraryListHeader(trailingAfterFilters: _tvWatchedViewToggle());
  }

  void _scheduleTvSeriesProgressSync() {
    if (_tvSeriesProgressSynced) {
      return;
    }
    _tvSeriesProgressSynced = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final username =
          ref.read(authControllerProvider).asData?.value.session?.username ?? '';
      if (username.isEmpty || !mounted) {
        return;
      }
      try {
        await recomputeTvSeriesWatchState(
          ref.read(apiClientProvider),
          username: username,
        );
        ref.invalidate(tvFullyWatchedSeriesLibraryProvider(username));
      } catch (_) {
        if (mounted) {
          setState(() => _tvSeriesProgressSynced = false);
        }
      }
    });
  }

  List<String> _tvWatchedSeriesMetaParts(TrackingItem item) {
    return [
      ...catalogRowMetaPartsForTrackingMedia(item.media),
      ...trackingTvProgressMetaParts(item),
    ];
  }

  List<TrackingItem> _filteredFullyWatchedSeries(TrackingListData data) {
    return _sortedTrackingItems(
      data.items
          .where((item) => trackingItemMatchesLibrarySearch(item, _searchQuery))
          .where(
            (item) => _filterModel.passesTrackingItem(
                  item,
                  collectionKind: widget.kind,
                  mediaScope: widget.mediaScope,
                ),
          )
          .toList(),
    );
  }

  Set<String>? _activeTvWatchingMediaIds() {
    if (widget.kind != LibraryCollectionKind.doing ||
        widget.mediaScope != LibraryMediaScope.tv) {
      return null;
    }
    final username =
        ref.read(authControllerProvider).asData?.value.session?.username ?? '';
    if (username.isEmpty) {
      return null;
    }
    final homeAsync = ref.watch(tvHomeShelvesProvider(username));
    return homeAsync.when(
      data: (home) => tvActiveWatchingMediaIdsFromShelves(
        nextUp: home.nextUp,
        upcomingEpisodes: home.upcomingEpisodes,
      ),
      loading: () => null,
      error: (_, _) => null,
    );
  }

  List<TrackingItem> matchedKindItems(TrackingListData data) {
    final activeTvIds = _activeTvWatchingMediaIds();
    return data.items
        .where((item) => _matchesFilter(item, activeTvWatchingIds: activeTvIds))
        .toList();
  }

  List<TrackingItem> trackingItemsForList(TrackingListData data) {
    return matchedKindItems(data)
        .where((i) => trackingItemMatchesLibrarySearch(i, _searchQuery))
        .where(
          (i) => _filterModel.passesTrackingItem(
                i,
                collectionKind: widget.kind,
                mediaScope: widget.mediaScope,
              ),
        )
        .toList();
  }

  bool get _usesSimpleRowStyle => switch (widget.kind) {
        LibraryCollectionKind.later ||
        LibraryCollectionKind.buy ||
        LibraryCollectionKind.doing ||
        LibraryCollectionKind.finished ||
        LibraryCollectionKind.left =>
          true,
        LibraryCollectionKind.owned => false,
      };

  bool get _usesCollectedPosterGrid => widget.kind == LibraryCollectionKind.owned;

  bool get _usesFinishedDateGrouping => widget.kind == LibraryCollectionKind.finished;

  List<String> Function(TrackingItem item)? get _scopedTrackingMetaParts =>
      widget.mediaScope == LibraryMediaScope.music
          ? (item) => catalogRowMetaPartsForTrackingMedia(
                item.media,
                mediaTypeOverride: 'music',
              )
          : null;

  String get _queueRemoveTooltip => switch (widget.kind) {
        LibraryCollectionKind.later => 'Remove from Later',
        LibraryCollectionKind.buy => 'Remove from Buy',
        LibraryCollectionKind.doing => 'Remove from Watching',
        LibraryCollectionKind.finished => 'Remove from Finished',
        LibraryCollectionKind.owned => 'Remove from Collected',
        LibraryCollectionKind.left => 'Remove from Left',
      };

  IconData get _queueRemoveIcon => switch (widget.kind) {
        LibraryCollectionKind.later => Icons.bookmark_remove_outlined,
        LibraryCollectionKind.buy => Icons.remove_shopping_cart_outlined,
        LibraryCollectionKind.doing => Icons.play_disabled_outlined,
        LibraryCollectionKind.finished => Icons.check_circle_outline,
        LibraryCollectionKind.owned => Icons.inventory_2_outlined,
        LibraryCollectionKind.left => Icons.outlined_flag_outlined,
      };

  Future<String> Function(TrackingMutationController) _queueRemoveMutation(
    TrackingItem item,
  ) {
    switch (widget.kind) {
      case LibraryCollectionKind.later:
        return (controller) => controller.toggleWatchlist(
              username: item.username,
              media: item.media,
              tracking: item,
            );
      case LibraryCollectionKind.buy:
        return (controller) => controller.toggleBuy(
              username: item.username,
              media: item.media,
              tracking: item,
            );
      case LibraryCollectionKind.doing:
        return (controller) async {
          if (trackingIsDoing(item)) {
            return controller.toggleDoing(
              username: item.username,
              media: item.media,
              tracking: item,
            );
          }
          return controller.toggleDropped(
            username: item.username,
            media: item.media,
            tracking: item,
          );
        };
      case LibraryCollectionKind.finished:
        return (controller) => controller.toggleWatched(
              username: item.username,
              media: item.media,
              tracking: item,
            );
      case LibraryCollectionKind.owned:
        return (controller) => controller.toggleCollected(
              username: item.username,
              media: item.media,
              tracking: item,
            );
      case LibraryCollectionKind.left:
        return (controller) => controller.toggleDropped(
              username: item.username,
              media: item.media,
              tracking: item,
            );
    }
  }

  Future<void> _promptCollectedLent(TrackingItem item) async {
    final submit = await showCollectedLentDialog(context);
    if (!mounted || submit == null) {
      return;
    }
    await runTrackingMutation(
      item: item,
      mutation: (controller) => controller.setCollectedLent(
        username: item.username,
        media: item.media,
        tracking: item,
        borrowerName: submit.borrowerName,
        lentAtUtc: submit.lentAtUtc,
      ),
    );
  }

  Widget _collectedGridSection({
    required List<TrackingItem> items,
    required Widget Function(TrackingItem item) itemBuilder,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 6,
        childAspectRatio: CollectedCatalogPosterCard.gridChildAspectRatio,
      ),
      itemBuilder: (context, index) => itemBuilder(items[index]),
    );
  }

  Widget _collectedPosterGrid(BuildContext context, List<TrackingItem> items) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 8, 16, 132),
      children: [
        libraryListHeader(),
        _collectedGridSection(
          items: items,
          itemBuilder: (item) {
            final m = item.media;
            return CollectedCatalogPosterCard(
              media: m,
              tracking: item,
              ownership: resolveCollectedOwnership(tracking: item, media: m),
              removing: _savingIds.contains(item.id),
              ownershipBusy: _savingIds.contains(item.id),
              onTap: () => context.push(catalogItemDetailPath(m)),
              onLongPress: () => _promptCollectedLent(item),
              onRemove: () => runTrackingMutation(
                item: item,
                mutation: _queueRemoveMutation(item),
              ),
              onOwnershipChanged: (pick) => runTrackingMutation(
                item: item,
                mutation: (controller) => controller.saveCollectedOwnership(
                  username: item.username,
                  media: item.media,
                  tracking: item,
                  variant: pick.variant,
                  price: pick.price,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTvWatchedBody() {
    final username =
        ref.watch(authControllerProvider).asData?.value.session?.username ?? '';

    if (_tvWatchedViewMode == TvWatchedLibraryViewMode.series) {
      if (!_tvSeriesProgressSynced) {
        _scheduleTvSeriesProgressSync();
      }
      final seriesAsync = ref.watch(tvFullyWatchedSeriesLibraryProvider(username));
      return seriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(tvFullyWatchedSeriesLibraryProvider(username)),
        ),
        data: (TrackingListData data) {
          final baseItems = data.items;
          final items = _filteredFullyWatchedSeries(data);
          if (baseItems.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 8, 16, 132),
              children: [
                _tvWatchedListHeader(),
                const SizedBox(height: 24),
                EmptyState(
                  title: _title,
                  message: _tvWatchedSeriesEmptyMessage,
                  icon: _icon,
                ),
              ],
            );
          }
          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 8, 16, 132),
              children: [
                _tvWatchedListHeader(),
                const SizedBox(height: 24),
                EmptyState(
                  title: 'No matches',
                  message: 'Nothing matches the current filters.',
                  icon: Icons.filter_alt_outlined,
                ),
              ],
            );
          }
          return _finishedDateGroupedList(
            context,
            items,
            header: _tvWatchedListHeader(),
            metaPartsForItem: _tvWatchedSeriesMetaParts,
          );
        },
      );
    }

    final episodesAsync = ref.watch(tvWatchedEpisodesLibraryProvider);
    final tvTrackingAsync = ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.tv));
    return episodesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(tvWatchedEpisodesLibraryProvider),
      ),
      data: (TvWatchedEpisodesLibraryData libData) {
        final scores = scoresByMediaId(tvTrackingAsync.asData?.value);
        final rows = libData.items
            .where((r) => tvWatchedEpisodeRowMatchesLibrarySearch(r, _searchQuery))
            .where(
              (r) => _filterModel.passesTvEpisodeRow(
                    r,
                    collectionKind: widget.kind,
                    mediaScope: widget.mediaScope,
                    scoresByMediaId: scores,
                  ),
            )
            .toList();
        sortTvWatchedEpisodeRowsInPlace(
          rows,
          key: _sortKey,
          direction: _sortDirection,
          scoresByMediaId: scores,
        );
        if (libData.items.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 8, 16, 132),
            children: [
              _tvWatchedListHeader(),
              const SizedBox(height: 24),
              EmptyState(title: _title, message: _emptyMessage, icon: _icon),
            ],
          );
        }
        if (rows.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 8, 16, 132),
            children: [
              _tvWatchedListHeader(),
              const SizedBox(height: 24),
              EmptyState(
                title: 'No matches',
                message: 'Nothing matches the current filters.',
                icon: Icons.filter_alt_outlined,
              ),
            ],
          );
        }
        return TvWatchedHistoryBody(
          filterHeader: _tvWatchedListHeader(),
          rows: rows,
          scoresByMediaId: scores,
          busyKeys: _tvEpisodeUnwatchBusy,
          busyKeyFor: tvEpisodeBusyKey,
          onOpenEpisode: (row) {
            context.push(
              '/tv/${row.media.id}/seasons/${row.seasonNumber}/episodes/${row.episodeNumber}',
            );
          },
          onRemoveWatched: unwatchTvEpisode,
        );
      },
    );
  }

  Widget _finishedDateGroupedList(
    BuildContext context,
    List<TrackingItem> items, {
    Widget? header,
    List<String> Function(TrackingItem item)? metaPartsForItem,
  }) {
    return FinishedTrackingHistoryBody(
      filterHeader: header,
      items: items,
      savingIds: _savingIds,
      removeTooltip: _queueRemoveTooltip,
      removeIcon: _queueRemoveIcon,
      metaPartsForItem: metaPartsForItem,
      onOpen: (item) => context.push(catalogItemDetailPath(item.media)),
      onRemove: (item) => runTrackingMutation(
        item: item,
        mutation: _queueRemoveMutation(item),
      ),
    );
  }

  Widget _simpleQueueList(
    BuildContext context,
    List<TrackingItem> items, {
    Widget? header,
    List<String> Function(TrackingItem item)? metaPartsForItem,
  }) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 8, 16, 132),
      children: [
        header ?? libraryListHeader(),
        for (final item in items) ...[
          LibraryWatchedStyleCatalogRow(
            title: item.media.title,
            imageUrl: item.media.imageUrl,
            metaParts: metaPartsForItem?.call(item) ??
                catalogRowMetaPartsForTrackingMedia(item.media),
            accentColor: accent,
            score: item.score,
            onTap: () {
              final m = item.media;
              context.push(catalogItemDetailPath(m));
            },
            trailing: IconButton(
              tooltip: _queueRemoveTooltip,
              iconSize: 18,
              onPressed: _savingIds.contains(item.id)
                  ? null
                  : () => runTrackingMutation(
                        item: item,
                        mutation: _queueRemoveMutation(item),
                      ),
              icon: _savingIds.contains(item.id)
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _queueRemoveIcon,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Future<void> _refreshTvWatchedData() async {
    final username =
        ref.read(authControllerProvider).asData?.value.session?.username ?? '';
    ref.invalidate(tvWatchedEpisodesLibraryProvider);
    if (username.isEmpty) {
      await ref.read(tvWatchedEpisodesLibraryProvider.future);
      return;
    }
    if (_tvWatchedViewMode == TvWatchedLibraryViewMode.series) {
      await recomputeTvSeriesWatchState(
        ref.read(apiClientProvider),
        username: username,
      );
      ref.invalidate(tvFullyWatchedSeriesLibraryProvider(username));
    }
    ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.tv));
    await Future.wait([
      ref.read(tvWatchedEpisodesLibraryProvider.future),
      if (_tvWatchedViewMode == TvWatchedLibraryViewMode.series)
        ref.read(tvFullyWatchedSeriesLibraryProvider(username).future),
      ref.read(libraryTrackingForScopeProvider(LibraryMediaScope.tv).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isTvWatched =
        widget.kind == LibraryCollectionKind.finished && widget.mediaScope == LibraryMediaScope.tv;
    final isWatchedHistoryPage = isTvWatched;
    final hideLayoutMenu =
        isWatchedHistoryPage || _usesSimpleRowStyle || _usesCollectedPosterGrid;

    final Widget bodyChild;
    if (isTvWatched) {
      bodyChild = _buildTvWatchedBody();
    } else {
      bodyChild = ref.watch(libraryTrackingForScopeProvider(widget.mediaScope)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => ErrorState(
              error: error,
              onRetry: () => ref.invalidate(libraryTrackingForScopeProvider(widget.mediaScope)),
            ),
            data: (TrackingListData data) {
              final baseItems = matchedKindItems(data);
              final items = _sortedTrackingItems(trackingItemsForList(data));
              if (baseItems.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 8, 16, 132),
                  children: [
                    libraryListHeader(),
                    const SizedBox(height: 24),
                    EmptyState(title: _title, message: _emptyMessage, icon: _icon),
                  ],
                );
              }
              if (items.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 8, 16, 132),
                  children: [
                    libraryListHeader(),
                    const SizedBox(height: 24),
                    EmptyState(
                      title: 'No matches',
                      message: 'Nothing matches the current filters.',
                      icon: Icons.filter_alt_outlined,
                    ),
                  ],
                );
              }
              if (_usesCollectedPosterGrid) {
                return _collectedPosterGrid(context, items);
              }
              if (_usesFinishedDateGrouping) {
                return _finishedDateGroupedList(
                  context,
                  items,
                  header: libraryListHeader(),
                  metaPartsForItem: _scopedTrackingMetaParts,
                );
              }
              return _simpleQueueList(
                context,
                items,
                metaPartsForItem: _scopedTrackingMetaParts,
              );
            },
          );
    }

    return Scaffold(
      extendBody: true,
      appBar: CulturAppBar(
        additionalActions: [
          IconButton(
            tooltip: 'Sort by',
            icon: const Icon(Icons.sort),
            onPressed: () => _openSortSheet(tvEpisodeSortContext: isTvWatched),
          ),
          if (!hideLayoutMenu)
            PopupMenuButton<LibraryViewMode>(
              tooltip: 'Change layout',
              icon: Icon(_viewMode.icon),
              onSelected: (mode) {
                setState(() {
                  _viewMode = mode;
                });
              },
              itemBuilder: (context) => [
                for (final mode in LibraryViewMode.values)
                  PopupMenuItem<LibraryViewMode>(
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
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (isTvWatched) {
            await _refreshTvWatchedData();
          } else {
            ref.invalidate(libraryTrackingForScopeProvider(widget.mediaScope));
            await ref.read(libraryTrackingForScopeProvider(widget.mediaScope).future);
          }
        },
        child: bodyChild,
      ),
      bottomNavigationBar: FloatingLibraryNav(
        currentDestination: switch (widget.kind) {
          LibraryCollectionKind.later => FloatingLibraryDestination.later,
          LibraryCollectionKind.buy => FloatingLibraryDestination.buy,
          LibraryCollectionKind.doing => FloatingLibraryDestination.doing,
          LibraryCollectionKind.finished => FloatingLibraryDestination.finished,
          LibraryCollectionKind.owned => FloatingLibraryDestination.owned,
          LibraryCollectionKind.left => FloatingLibraryDestination.left,
        },
        mediaScope: widget.mediaScope,
      ),
    );
  }

  String get _title => widget.mediaScope.collectionPageTitle(widget.kind);

  String get _emptyMessage => switch (widget.kind) {
    LibraryCollectionKind.later => switch (widget.mediaScope) {
        LibraryMediaScope.game =>
          'Games you save for later will appear here.',
        LibraryMediaScope.boardgame =>
          'Board games you save for later will appear here.',
        LibraryMediaScope.book => 'Books you save for later will appear here.',
        LibraryMediaScope.tv => 'TV shows you save for later will appear here.',
        LibraryMediaScope.music => 'Albums you save for later will appear here.',
        LibraryMediaScope.movie => 'Movies you save for later will appear here.',
      },
    LibraryCollectionKind.buy => switch (widget.mediaScope) {
        LibraryMediaScope.game => 'Games you want to buy appear here.',
        LibraryMediaScope.boardgame => 'Board games you want to buy appear here.',
        LibraryMediaScope.book => 'Books you want to buy appear here.',
        LibraryMediaScope.music => 'Albums you want to buy appear here.',
        LibraryMediaScope.tv =>
          'Series you want to buy or collect on disc appear here.',
        LibraryMediaScope.movie => 'Films you want to buy or collect appear here.',
      },
    LibraryCollectionKind.doing => switch (widget.mediaScope) {
        LibraryMediaScope.game => 'Games you are playing appear here.',
        LibraryMediaScope.boardgame => 'Board games you are playing appear here.',
        LibraryMediaScope.book => 'Books you are reading appear here.',
        LibraryMediaScope.music => 'Albums you are listening to appear here.',
        LibraryMediaScope.tv => 'Shows you are actively watching appear here.',
        LibraryMediaScope.movie =>
          'Movies you are currently watching appear here.',
      },
    LibraryCollectionKind.finished => switch (widget.mediaScope) {
        LibraryMediaScope.game =>
          'Games you mark as played are grouped by the day you finished them.',
        LibraryMediaScope.boardgame => 'Board games you mark as played are grouped by the day you finished them.',
        LibraryMediaScope.book =>
          'Books you mark as read are grouped by the day you finished them.',
        LibraryMediaScope.music =>
          'Albums you mark as listened are grouped by the day you finished them.',
        LibraryMediaScope.tv =>
          'Episodes you mark as finished are grouped by day. Pull to refresh after changes elsewhere.',
        LibraryMediaScope.movie =>
          'Movies you mark as finished are grouped by the day you completed them.',
      },
    LibraryCollectionKind.owned => switch (widget.mediaScope) {
        LibraryMediaScope.game => 'Games you own will appear here.',
        LibraryMediaScope.boardgame => 'Board games you own will appear here.',
        LibraryMediaScope.book => 'Books you own will appear here.',
        LibraryMediaScope.music => 'Albums you own will appear here.',
        LibraryMediaScope.tv => 'Series you own will appear here.',
        LibraryMediaScope.movie => 'Movies you own will appear here.',
      },
    LibraryCollectionKind.left => switch (widget.mediaScope) {
        LibraryMediaScope.game => 'Games you dropped or set aside appear here.',
        LibraryMediaScope.boardgame => 'Board games you dropped or set aside appear here.',
        LibraryMediaScope.book => 'Books you dropped or set aside appear here.',
        LibraryMediaScope.music => 'Albums you set aside or dropped appear here.',
        LibraryMediaScope.tv => 'Shows you set aside or dropped appear here.',
        LibraryMediaScope.movie => 'Movies you set aside or dropped appear here.',
      },
  };

  String get _tvWatchedSeriesEmptyMessage =>
      'Shows where you have watched every aired episode across all seasons appear here.';

  IconData get _icon => switch (widget.kind) {
    LibraryCollectionKind.later => Icons.bookmark_border_outlined,
    LibraryCollectionKind.buy => Icons.shopping_bag_outlined,
    LibraryCollectionKind.doing => Icons.play_circle_outline,
    LibraryCollectionKind.finished => Icons.check_circle_outline,
    LibraryCollectionKind.owned => Icons.inventory_2_outlined,
    LibraryCollectionKind.left => Icons.flag_outlined,
  };

  bool _matchesFilter(TrackingItem item, {Set<String>? activeTvWatchingIds}) {
    return switch (widget.kind) {
      LibraryCollectionKind.later => trackingIsInWatchlist(item),
      LibraryCollectionKind.buy => trackingIsBuy(item) && !trackingIsDropped(item),
      LibraryCollectionKind.doing => trackingIsInWatchingCollection(
          item,
          activeTvMediaIds: activeTvWatchingIds,
        ),
      LibraryCollectionKind.finished => trackingIsWatched(item),
      LibraryCollectionKind.owned => hasTrackingFlag(item, kCollectedTrackingFlag),
      LibraryCollectionKind.left => trackingIsDropped(item),
    };
  }
}

void sortTrackingItemsInPlace(
  List<TrackingItem> items, {
  required LibraryTrackingSortKey key,
  required LibrarySortDirection direction,
}) {
  if (key == LibraryTrackingSortKey.defaultOrder || items.length < 2) {
    return;
  }
  final last = direction == LibrarySortDirection.last;

  int tieBreak(TrackingItem a, TrackingItem b) => a.id.compareTo(b.id);

  int cmp(TrackingItem a, TrackingItem b) {
    switch (key) {
      case LibraryTrackingSortKey.defaultOrder:
        return 0;
      case LibraryTrackingSortKey.markedWatched:
        final c = compareNullableDate(a.completedAt, b.completedAt, lastMeansNewest: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.markedOwned:
        final c = compareNullableDate(a.collectedAt, b.collectedAt, lastMeansNewest: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.markedDropped:
        final c = compareNullableDate(a.droppedAt, b.droppedAt, lastMeansNewest: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.watchHistoryEntries:
        final ca = a.episodeWatchedCount;
        final cb = b.episodeWatchedCount;
        final c = compareNullableInt(ca, cb, lastMeansHigh: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.ratingEdited:
        final c = compareNullableDate(a.updatedAt, b.updatedAt, lastMeansNewest: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.myRating:
        final c = compareNullableNum(a.score, b.score, lastMeansHigh: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.tmdbRating:
        final va = catalogTmdbVoteAverage(a.media);
        final vb = catalogTmdbVoteAverage(b.media);
        final c = compareNullableNum(va, vb, lastMeansHigh: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.addedToList:
        final ta = a.updatedAt ?? a.createdAt;
        final tb = b.updatedAt ?? b.createdAt;
        final c = compareNullableDate(ta, tb, lastMeansNewest: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.firstReleaseDate:
        final da = sortCatalogReleaseDate(a.media);
        final db = sortCatalogReleaseDate(b.media);
        final c = compareNullableDate(da, db, lastMeansNewest: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.title:
        final c = compareStrings(a.media.title, b.media.title, lastMeansDescAlpha: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.runtime:
        final ra = catalogRuntimeMinutes(a.media);
        final rb = catalogRuntimeMinutes(b.media);
        final c = compareNullableInt(ra, rb, lastMeansHigh: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.newestEpisodeAirDate:
        final da = sortCatalogAirDate(a.media);
        final db = sortCatalogAirDate(b.media);
        final c = compareNullableDate(da, db, lastMeansNewest: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.episodeRuntime:
        final ra = sortMetaInt(a.media, ['episodeRuntimeMinutes', 'episodeRunTime', 'episode_runtime']);
        final rb = sortMetaInt(b.media, ['episodeRuntimeMinutes', 'episodeRunTime', 'episode_runtime']);
        final c = compareNullableInt(ra, rb, lastMeansHigh: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.numberOfSeasons:
        final sa = sortMetaInt(a.media, ['numberOfSeasons', 'number_of_seasons']);
        final sb = sortMetaInt(b.media, ['numberOfSeasons', 'number_of_seasons']);
        final c = compareNullableInt(sa, sb, lastMeansHigh: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.gross:
        final ga = sortMetaInt(a.media, ['revenue', 'gross']);
        final gb = sortMetaInt(b.media, ['revenue', 'gross']);
        final c = compareNullableInt(ga, gb, lastMeansHigh: last);
        return c != 0 ? c : tieBreak(a, b);
      case LibraryTrackingSortKey.budget:
        final ba = sortMetaInt(a.media, ['budget']);
        final bb = sortMetaInt(b.media, ['budget']);
        final c = compareNullableInt(ba, bb, lastMeansHigh: last);
        return c != 0 ? c : tieBreak(a, b);
    }
  }

  items.sort(cmp);
}

void sortTvWatchedEpisodeRowsInPlace(
  List<WatchedTvEpisodeLibraryRow> rows, {
  required LibraryTrackingSortKey key,
  required LibrarySortDirection direction,
  required Map<String, double> scoresByMediaId,
}) {
  if (key == LibraryTrackingSortKey.defaultOrder || rows.length < 2) {
    return;
  }
  final last = direction == LibrarySortDirection.last;

  int tie(WatchedTvEpisodeLibraryRow a, WatchedTvEpisodeLibraryRow b) {
    final c = a.media.id.compareTo(b.media.id);
    if (c != 0) {
      return c;
    }
    if (a.seasonNumber != b.seasonNumber) {
      return a.seasonNumber.compareTo(b.seasonNumber);
    }
    return a.episodeNumber.compareTo(b.episodeNumber);
  }

  int cmp(WatchedTvEpisodeLibraryRow a, WatchedTvEpisodeLibraryRow b) {
    switch (key) {
      case LibraryTrackingSortKey.defaultOrder:
        return 0;
      case LibraryTrackingSortKey.markedWatched:
        final da = parseWatchInstant(a.watchedAt);
        final db = parseWatchInstant(b.watchedAt);
        final c = compareNullableDate(da, db, lastMeansNewest: last);
        return c != 0 ? c : tie(a, b);
      case LibraryTrackingSortKey.myRating:
        final sa = scoresByMediaId[a.media.id];
        final sb = scoresByMediaId[b.media.id];
        final c = compareNullableNum(sa, sb, lastMeansHigh: last);
        return c != 0 ? c : tie(a, b);
      case LibraryTrackingSortKey.tmdbRating:
        final va = catalogTmdbVoteAverage(a.media);
        final vb = catalogTmdbVoteAverage(b.media);
        final c = compareNullableNum(va, vb, lastMeansHigh: last);
        return c != 0 ? c : tie(a, b);
      case LibraryTrackingSortKey.title:
        final la = '${a.media.title} ${a.seasonEpisodeLabel}';
        final lb = '${b.media.title} ${b.seasonEpisodeLabel}';
        final c = compareStrings(la, lb, lastMeansDescAlpha: last);
        return c != 0 ? c : tie(a, b);
      case LibraryTrackingSortKey.firstReleaseDate:
        final da = sortCatalogReleaseDate(a.media);
        final db = sortCatalogReleaseDate(b.media);
        final c = compareNullableDate(da, db, lastMeansNewest: last);
        return c != 0 ? c : tie(a, b);
      default:
        return tie(a, b);
    }
  }

  rows.sort(cmp);
}

String _sortKeyTitle(LibraryTrackingSortKey k) {
  return switch (k) {
    LibraryTrackingSortKey.defaultOrder => 'Default (server order)',
    LibraryTrackingSortKey.markedWatched => 'Marked as finished',
    LibraryTrackingSortKey.markedOwned => 'Marked as owned',
    LibraryTrackingSortKey.markedDropped => 'Marked as dropped',
    LibraryTrackingSortKey.watchHistoryEntries => 'Amount: Watch history entries',
    LibraryTrackingSortKey.ratingEdited => 'Rating added / edited',
    LibraryTrackingSortKey.myRating => 'My rating',
    LibraryTrackingSortKey.tmdbRating => 'TMDb vote average',
    LibraryTrackingSortKey.addedToList => 'Added to this list',
    LibraryTrackingSortKey.firstReleaseDate => 'First release date',
    LibraryTrackingSortKey.title => 'Title',
    LibraryTrackingSortKey.runtime => 'Runtime',
    LibraryTrackingSortKey.newestEpisodeAirDate => 'Newest episode air date',
    LibraryTrackingSortKey.episodeRuntime => 'Episode runtime',
    LibraryTrackingSortKey.numberOfSeasons => 'Number of seasons',
    LibraryTrackingSortKey.gross => 'Gross',
    LibraryTrackingSortKey.budget => 'Budget',
  };
}

String? _sortKeyHint(LibraryTrackingSortKey k, LibraryMediaScope mediaScope) {
  return switch (k) {
    LibraryTrackingSortKey.watchHistoryEntries => '(TV shows: episode watches)',
    LibraryTrackingSortKey.runtime when mediaScope == LibraryMediaScope.tv => '(show metadata)',
    LibraryTrackingSortKey.runtime => '(only movies)',
    LibraryTrackingSortKey.newestEpisodeAirDate => '(only shows)',
    LibraryTrackingSortKey.episodeRuntime => '(only shows)',
    LibraryTrackingSortKey.numberOfSeasons => '(only shows)',
    LibraryTrackingSortKey.gross => '(only movies)',
    LibraryTrackingSortKey.budget => '(only movies)',
    _ => null,
  };
}

Iterable<LibraryTrackingSortKey> _sortKeysForScope(LibraryMediaScope mediaScope) sync* {
  yield LibraryTrackingSortKey.defaultOrder;
  yield LibraryTrackingSortKey.markedWatched;
  yield LibraryTrackingSortKey.markedOwned;
  yield LibraryTrackingSortKey.markedDropped;
  if (mediaScope == LibraryMediaScope.tv) {
    yield LibraryTrackingSortKey.watchHistoryEntries;
  }
  yield LibraryTrackingSortKey.ratingEdited;
  yield LibraryTrackingSortKey.myRating;
  yield LibraryTrackingSortKey.tmdbRating;
  yield LibraryTrackingSortKey.addedToList;
  yield LibraryTrackingSortKey.firstReleaseDate;
  yield LibraryTrackingSortKey.title;
  yield LibraryTrackingSortKey.runtime;
  if (mediaScope == LibraryMediaScope.tv) {
    yield LibraryTrackingSortKey.newestEpisodeAirDate;
    yield LibraryTrackingSortKey.episodeRuntime;
    yield LibraryTrackingSortKey.numberOfSeasons;
  } else {
    yield LibraryTrackingSortKey.gross;
    yield LibraryTrackingSortKey.budget;
  }
}

Iterable<LibraryTrackingSortKey> _sortKeysForTvEpisodes() sync* {
  yield LibraryTrackingSortKey.defaultOrder;
  yield LibraryTrackingSortKey.markedWatched;
  yield LibraryTrackingSortKey.myRating;
  yield LibraryTrackingSortKey.tmdbRating;
  yield LibraryTrackingSortKey.firstReleaseDate;
  yield LibraryTrackingSortKey.title;
}

Future<void> showLibraryTrackingSortSheet(
  BuildContext context, {
  required LibraryMediaScope mediaScope,
  required bool tvEpisodeSortContext,
  required LibraryTrackingSortKey currentKey,
  required LibrarySortDirection currentDirection,
  required void Function(LibraryTrackingSortKey key, LibrarySortDirection direction) onApply,
}) async {
  final theme = Theme.of(context);
  final allowed = (tvEpisodeSortContext ? _sortKeysForTvEpisodes() : _sortKeysForScope(mediaScope)).toSet();
  var key = allowed.contains(currentKey) ? currentKey : LibraryTrackingSortKey.defaultOrder;
  var direction = currentDirection;
  final keys = tvEpisodeSortContext ? _sortKeysForTvEpisodes() : _sortKeysForScope(mediaScope);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: theme.colorScheme.surfaceContainerLow,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModal) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text('Sort by', style: theme.textTheme.titleLarge),
                  ),
                  const SizedBox(height: 4),
                  RadioGroup<LibraryTrackingSortKey>(
                    groupValue: key,
                    onChanged: (v) {
                      if (v != null) {
                        setModal(() => key = v);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final k in keys)
                          RadioListTile<LibraryTrackingSortKey>(
                            title: Text(_sortKeyTitle(k)),
                            subtitle: _sortKeyHint(k, mediaScope) != null
                                ? Text(
                                    _sortKeyHint(k, mediaScope)!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                : null,
                            value: k,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Order', style: theme.textTheme.titleSmall),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SegmentedButton<LibrarySortDirection>(
                      segments: const [
                        ButtonSegment(
                          value: LibrarySortDirection.last,
                          label: Text('Last'),
                          icon: Icon(Icons.south),
                        ),
                        ButtonSegment(
                          value: LibrarySortDirection.first,
                          label: Text('First'),
                          icon: Icon(Icons.north),
                        ),
                      ],
                      selected: {direction},
                      onSelectionChanged: (s) {
                        if (s.isNotEmpty) {
                          setModal(() => direction = s.first);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: FilledButton(
                      onPressed: () {
                        onApply(key, direction);
                        Navigator.pop(ctx);
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
