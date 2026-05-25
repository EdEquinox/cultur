import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/games/game_collection_link.dart';
import 'package:yamtrack/src/models/games/game_franchise_link.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/providers/catalog_detail_providers.dart';
import 'package:yamtrack/src/providers/catalog_tracking_providers.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/providers/games_home_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/screens/widgets/genres_tags_card.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_companies_section.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_detail_nav_row.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_hero_carousel.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_ratings_row.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_pending_catalog_banner.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_resolve_pending_sheet.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_time_to_beat_card.dart';
import 'package:yamtrack/src/screens/widgets/game_action_row.dart';
import 'package:yamtrack/src/models/rating_sheet_result.dart';
import 'package:yamtrack/src/screens/widgets/game_finish_playing_sheet.dart';
import 'package:yamtrack/src/screens/widgets/left_resume_sheet.dart';
import 'package:yamtrack/src/screens/widgets/game_lists_sheet.dart';
import 'package:yamtrack/src/screens/widgets/movie_rating_sheet.dart';
import 'package:yamtrack/src/screens/widgets/movie_recommendation_shelf.dart';
import 'package:yamtrack/src/screens/widgets/movie_video_shelf.dart';
import 'package:yamtrack/src/screens/widgets/media_detail_links_section.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/collected_toggle_flow.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class GameDetailPage extends ConsumerStatefulWidget {
  const GameDetailPage({required this.mediaId, super.key});

  final String mediaId;

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage> {
  bool _isSaving = false;
  bool _showFullOverview = false;

  CatalogDetailRequest get _request {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    return CatalogDetailRequest(
      mediaId: widget.mediaId,
      username: username,
      kind: CatalogDetailKind.game,
    );
  }

  Future<void> _runTrackingMutation({
    required Future<String?> Function(TrackingMutationController controller, String username)
        mutation,
  }) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to update tracking.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final message = await mutation(ref.read(trackingMutationControllerProvider), username);
      if (message == null) {
        return;
      }
      ref.invalidate(catalogDetailProvider(_request));
      ref.invalidate(gameSearchTrackingProvider(username));
      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.game));
      invalidateGamesHomeCaches(ref, username: username);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showRatingSheet(CatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }
    var stars = detail.tracking?.score?.round().clamp(0, 10) ?? 0;
    final hasExisting = detail.tracking?.score != null;

    final result = await showModalBottomSheet<RatingSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return MovieRatingSheet(
              title: 'Rate this game',
              prompt: 'Rate game?',
              hasExistingRating: hasExisting,
              selectedStars: stars,
              onStarsChanged: (value) => setModalState(() => stars = value),
              onCancel: () => Navigator.of(context).pop(const RatingSheetDismissed()),
              onSave: () {
                if (stars <= 0) {
                  Navigator.of(context).pop(const RatingSheetRemoved());
                } else {
                  Navigator.of(context).pop(RatingSheetSet(stars.toDouble()));
                }
              },
            );
          },
        );
      },
    );

    switch (result) {
      case null:
      case RatingSheetDismissed():
        return;
      case RatingSheetRemoved():
        await _runTrackingMutation(
          mutation: (controller, user) => controller.saveRating(
            username: user,
            media: detail.media,
            tracking: detail.tracking,
            remove: true,
          ),
        );
      case RatingSheetSet(:final score):
        await _runTrackingMutation(
          mutation: (controller, user) => controller.saveRating(
            username: user,
            media: detail.media,
            tracking: detail.tracking,
            score: score,
          ),
        );
    }
  }

  bool _isActivelyPlaying(CatalogDetail detail) =>
      trackingIsActivelyDoing(detail.tracking);

  Future<void> _onPlayingTap(CatalogDetail detail) async {
    if (_isActivelyPlaying(detail)) {
      await _showFinishPlayingSheet(detail);
      return;
    }

    if (trackingIsDropped(detail.tracking)) {
      await _showLeftResumeSheet(detail);
      return;
    }

    await _runTrackingMutation(
      mutation: (controller, username) => controller.toggleDoing(
        username: username,
        media: detail.media,
        tracking: detail.tracking,
      ),
    );
  }

  Future<void> _showLeftResumeSheet(CatalogDetail detail) async {
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<LeftResumeSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: LeftResumeSheet(
            headerTitle: 'Left',
            mediaTitle: detail.media.title,
            doingLabel: 'Resume playing',
            doingSubtitle: 'Moves to Playing',
            doneLabel: 'Mark as played',
            doneSubtitle: 'Moves to Played',
            initialScore: detail.tracking?.score,
          ),
        );
      },
    );
    if (result == null) {
      return;
    }

    if (result.outcome == LeftResumeOutcome.doing) {
      await _runTrackingMutation(
        mutation: (controller, username) => controller.toggleDoing(
          username: username,
          media: detail.media,
          tracking: detail.tracking,
        ),
      );
      return;
    }

    await _runTrackingMutation(
      mutation: (controller, username) => controller.finishPlayingGame(
        username: username,
        media: detail.media,
        tracking: detail.tracking,
        markAsPlayed: true,
        score: result.score,
        actionAtUtc: result.actionAtUtc,
      ),
    );
  }

  Future<void> _showFinishPlayingSheet(CatalogDetail detail) async {
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<GameFinishPlayingSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: GameFinishPlayingSheet(
            gameTitle: detail.media.title,
            initialScore: detail.tracking?.score,
          ),
        );
      },
    );
    if (result == null) {
      return;
    }

    if (result.outcome == GamePlayingOutcome.paused) {
      await _runTrackingMutation(
        mutation: (controller, username) => controller.pausePlayingGame(
              username: username,
              media: detail.media,
              tracking: detail.tracking,
            ),
      );
      return;
    }

    await _runTrackingMutation(
      mutation: (controller, username) => controller.finishPlayingGame(
            username: username,
            media: detail.media,
            tracking: detail.tracking,
            markAsPlayed: result.outcome == GamePlayingOutcome.played,
            score: result.score,
            actionAtUtc: result.actionAtUtc,
          ),
    );
  }

  Future<void> _togglePriority(CatalogDetail detail) async {
    await _runTrackingMutation(
      mutation: (controller, username) => controller.togglePriority(
            username: username,
            media: detail.media,
            tracking: detail.tracking,
          ),
    );
    ref.invalidate(customGameListsProvider);
    await ref.read(customGameListsProvider.future);
  }

  Widget _gameHeroPriorityPin(CatalogDetail detail) {
    final inPriority = trackingIsPriority(detail.tracking);
    return GameHeroOverlayPinButton(
      icon: inPriority ? Icons.push_pin : Icons.push_pin_outlined,
      tooltip: inPriority ? 'Remove from priority' : 'Priority — show in Next to play',
      onPressed: _isSaving ? null : () => _togglePriority(detail),
    );
  }

  Future<void> _showListsSheet(CatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to manage lists.')),
      );
      return;
    }

    Future<void> createList() async {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Create custom list'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'List name',
                hintText: 'Backlog, Co-op night, GOTY picks…',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
      SchedulerBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
      if (name == null || name.trim().isEmpty) {
        return;
      }
      final list = await ref
          .read(customGameListsControllerProvider)
          .createList(username, name.trim());
      await ref.read(customGameListsControllerProvider).toggleItem(
            username: username,
            listId: list.id,
            item: detail.media,
          );
      ref.invalidate(customGameListsProvider);
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final listsAsync = ref.watch(customGameListsProvider);
            return GameListsSheet(
              detail: detail,
              listsAsync: listsAsync,
              onCreateList: () async {
                await createList();
                ref.invalidate(customGameListsProvider);
              },
              onToggleList: (list) async {
                await ref.read(customGameListsControllerProvider).toggleItem(
                      username: username,
                      listId: list.id,
                      item: detail.media,
                    );
                ref.invalidate(customGameListsProvider);
              },
              onDone: () => Navigator.of(context).pop(),
            );
          },
        );
      },
    );
  }

  void _openFranchiseBrowse(GameFranchiseLink franchise) {
    if (!franchise.isValid) {
      return;
    }
    context.push(
      gamesByFranchiseBrowsePath(
        franchiseId: franchise.franchiseId,
        name: franchise.name,
      ),
    );
  }

  void _openCollectionBrowse(GameCollectionLink collection) {
    if (!collection.isValid) {
      return;
    }
    context.push(
      gamesByCollectionBrowsePath(
        collectionId: collection.collectionId,
        name: collection.name,
      ),
    );
  }

  Future<void> _openCollectionsBrowse(List<GameCollectionLink> collections) async {
    final valid = collections.where((c) => c.isValid).toList();
    if (valid.isEmpty) {
      return;
    }
    if (valid.length == 1) {
      _openCollectionBrowse(valid.first);
      return;
    }

    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                'Bundles and editions',
                style: CulturCatalogTypography.sectionHeading(theme),
              ),
              const SizedBox(height: 12),
              for (final collection in valid)
                ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(collection.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openCollectionBrowse(collection);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openResolvePendingSheet(CatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to link this game.')),
      );
      return;
    }
    final resolvedId = await showGameResolvePendingSheet(
      context: context,
      ref: ref,
      pendingMediaId: widget.mediaId,
      username: username,
      initialQuery: detail.media.title,
    );
    if (resolvedId == null || !mounted) {
      return;
    }
    ref.invalidate(catalogDetailProvider(_request));
    ref.invalidate(gameSearchTrackingProvider(username));
    ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.game));
    ref.invalidate(customGameListsProvider);
    invalidateGamesHomeCaches(ref, username: username);
    context.pushReplacement('/games/$resolvedId');
  }

  Future<void> _copyPrimaryLink(CatalogDetail detail) async {
    final primaryUrl = detail.links.isNotEmpty
        ? detail.links.first.url
        : 'https://www.igdb.com/games/${detail.media.externalId}';
    await Clipboard.setData(ClipboardData(text: primaryUrl));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(catalogDetailProvider(_request));

    return Scaffold(
      extendBody: true,
      appBar: const CulturAppBar(),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(catalogDetailProvider(_request)),
        ),
        data: (detail) => _GameDetailBody(
          detail: detail,
          isSaving: _isSaving,
          heroOverlayActions: _gameHeroPriorityPin(detail),
          showFullOverview: _showFullOverview,
          onToggleOverview: () => setState(() => _showFullOverview = !_showFullOverview),
          onCollectedToggle: () => _runTrackingMutation(
            mutation: (controller, username) => runCollectedToggle(
              context: context,
              controller: controller,
              username: username,
              media: detail.media,
              tracking: detail.tracking,
            ),
          ),
          onWatchlistToggle: () => _runTrackingMutation(
            mutation: (controller, username) => controller.toggleWatchlist(
              username: username,
              media: detail.media,
              tracking: detail.tracking,
            ),
          ),
          onDoingToggle: () => _onPlayingTap(detail),
          onBuyToggle: () => _runTrackingMutation(
            mutation: (controller, username) => controller.toggleBuy(
              username: username,
              media: detail.media,
              tracking: detail.tracking,
            ),
          ),
          onRateTap: () => _showRatingSheet(detail),
          onListsTap: () => _showListsSheet(detail),
          onOpenRecommendation: (item) => context.push(catalogItemDetailPath(item)),
          onOpenFranchise: _openFranchiseBrowse,
          onOpenCollections: _openCollectionsBrowse,
          onOpenVideo: _openExternalUrl,
          onShareTap: () => _copyPrimaryLink(detail),
          onOpenLink: _openExternalUrl,
          onResolvePending: detail.catalogPending
              ? () => _openResolvePendingSheet(detail)
              : null,
        ),
      ),
      bottomNavigationBar: const FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: LibraryMediaScope.game,
      ),
    );
  }
}

class _GameDetailBody extends StatelessWidget {
  const _GameDetailBody({
    required this.detail,
    required this.isSaving,
    this.heroOverlayActions,
    required this.showFullOverview,
    required this.onToggleOverview,
    required this.onCollectedToggle,
    required this.onWatchlistToggle,
    required this.onDoingToggle,
    required this.onBuyToggle,
    required this.onRateTap,
    required this.onListsTap,
    required this.onOpenRecommendation,
    required this.onOpenFranchise,
    required this.onOpenCollections,
    required this.onOpenVideo,
    required this.onShareTap,
    required this.onOpenLink,
    this.onResolvePending,
  });

  final CatalogDetail detail;
  final bool isSaving;
  final Widget? heroOverlayActions;
  final bool showFullOverview;
  final VoidCallback onToggleOverview;
  final VoidCallback onCollectedToggle;
  final VoidCallback onWatchlistToggle;
  final VoidCallback onDoingToggle;
  final VoidCallback onBuyToggle;
  final VoidCallback onRateTap;
  final VoidCallback onListsTap;
  final ValueChanged<CatalogItem> onOpenRecommendation;
  final ValueChanged<GameFranchiseLink> onOpenFranchise;
  final ValueChanged<List<GameCollectionLink>> onOpenCollections;
  final ValueChanged<String> onOpenVideo;
  final VoidCallback onShareTap;
  final ValueChanged<String> onOpenLink;
  final VoidCallback? onResolvePending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overview = detail.overview?.trim() ?? '';
    final collected = hasTrackingFlag(detail.tracking, kCollectedTrackingFlag);
    final watchlist = trackingIsInWatchlist(detail.tracking);
    final watched = trackingIsWatched(detail.tracking);
    final buy = trackingIsBuy(detail.tracking);
    final activelyPlaying = trackingIsActivelyDoing(detail.tracking);
    final dropped = trackingIsDropped(detail.tracking);
    final rating = detail.tracking?.score;

    final franchise = detail.gameFranchise;
    final collections = detail.gameCollections;
    final timeToBeat = detail.gameTimeToBeat;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        GameHeroCarousel(
          detail: detail,
          overlayActions: heroOverlayActions,
          onShareTap: onShareTap,
        ),
        if (onResolvePending != null) ...[
          const SizedBox(height: 12),
          GamePendingCatalogBanner(
            importSource: detail.importSource,
            onSearchCatalog: onResolvePending!,
          ),
        ],
        const SizedBox(height: 16),
        GameActionRow(
          isSaving: isSaving,
          isInLater: watchlist,
          isPlaying: activelyPlaying,
          isPlayed: watched,
          isBuy: buy,
          isOwned: collected,
          isDropped: dropped,
          rating: rating,
          onLaterTap: onWatchlistToggle,
          onPlayingTap: onDoingToggle,
          onBuyTap: onBuyToggle,
          onOwnedTap: onCollectedToggle,
          onRateTap: onRateTap,
          onListsTap: onListsTap,
        ),
        if (detail.gameDevelopers.isNotEmpty || detail.gamePublishers.isNotEmpty) ...[
          const SizedBox(height: 16),
          GameCompaniesSection(
            developers: detail.gameDevelopers,
            publishers: detail.gamePublishers,
          ),
        ],
        if (detail.ratings.isNotEmpty) ...[
          const SizedBox(height: 16),
          GameRatingsRow(ratings: detail.ratings),
        ],
        if (timeToBeat != null) ...[
          const SizedBox(height: 16),
          GameTimeToBeatCard(timeToBeat: timeToBeat),
        ],
        if (franchise != null && franchise.isValid) ...[
          const SizedBox(height: 12),
          GameDetailNavRow(
            icon: Icons.view_list_outlined,
            label: 'Game series',
            subtitle: franchise.name,
            onTap: () => onOpenFranchise(franchise),
          ),
        ],
        if (collections.isNotEmpty) ...[
          const SizedBox(height: 8),
          GameDetailNavRow(
            icon: Icons.account_tree_outlined,
            label: 'Bundles and editions',
            onTap: () => onOpenCollections(collections),
          ),
        ],
        if (detail.videos.isNotEmpty) ...[
          const SizedBox(height: 16),
          MovieVideoShelf(
            videos: detail.videos,
            onOpenVideo: onOpenVideo,
          ),
        ],
        if (detail.genres.isNotEmpty ||
            detail.gameModes.isNotEmpty ||
            detail.playerPerspectives.isNotEmpty ||
            detail.keywords.isNotEmpty) ...[
          const SizedBox(height: 16),
          GenresTagsCard(
            genres: detail.genres,
            keywords: [
              ...detail.gameModes,
              ...detail.playerPerspectives,
              ...detail.keywords,
            ],
          ),
        ],
        if (overview.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            overview,
            maxLines: showFullOverview ? null : 6,
            overflow: showFullOverview ? TextOverflow.visible : TextOverflow.ellipsis,
            style: CulturCatalogTypography.bodyText(theme, scheme),
          ),
          if (overview.length > 280) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onToggleOverview,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  showFullOverview ? 'Show less' : 'Read more',
                  style: CulturCatalogTypography.linkAction(theme, scheme),
                ),
              ),
            ),
          ],
        ],
        if (detail.recommendations.isNotEmpty) ...[
          const SizedBox(height: 20),
          MovieRecommendationShelf(
            items: detail.recommendations,
            onOpenRecommendation: onOpenRecommendation,
          ),
        ],
        if (detail.links.isNotEmpty) ...[
          const SizedBox(height: 24),
          MediaDetailLinksSection(
            links: detail.links,
            onOpenLink: onOpenLink,
          ),
        ],
      ],
    );
  }
}
