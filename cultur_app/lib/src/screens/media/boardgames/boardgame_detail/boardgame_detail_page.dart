import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/rating_sheet_result.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/boardgames_home_providers.dart';
import 'package:yamtrack/src/providers/catalog_detail_providers.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_hero_carousel.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_ratings_row.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/screens/widgets/boardgame_action_row.dart';
import 'package:yamtrack/src/screens/widgets/game_lists_sheet.dart';
import 'package:yamtrack/src/screens/widgets/media_detail_links_section.dart';
import 'package:yamtrack/src/screens/widgets/movie_rating_sheet.dart';
import 'package:yamtrack/src/utils/collected_toggle_flow.dart';
import 'package:yamtrack/src/utils/library_utils.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class BoardgameDetailPage extends ConsumerStatefulWidget {
  const BoardgameDetailPage({required this.mediaId, super.key});

  final String mediaId;

  @override
  ConsumerState<BoardgameDetailPage> createState() => _BoardgameDetailPageState();
}

class _BoardgameDetailPageState extends ConsumerState<BoardgameDetailPage> {
  bool _isSaving = false;
  bool _showFullOverview = false;

  CatalogDetailRequest get _request {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    return CatalogDetailRequest(
      mediaId: widget.mediaId,
      username: username,
      kind: CatalogDetailKind.boardgame,
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
      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.boardgame));
      ref.invalidate(customBoardgameListsProvider);
      invalidateBoardgamesHomeCaches(ref, username: username);
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

  Future<void> _togglePriority(CatalogDetail detail) async {
    await _runTrackingMutation(
      mutation: (controller, username) => controller.togglePriority(
        username: username,
        media: detail.media,
        tracking: detail.tracking,
      ),
    );
  }

  Widget _heroPriorityPin(CatalogDetail detail) {
    final inPriority = trackingIsPriority(detail.tracking);
    return GameHeroOverlayPinButton(
      icon: inPriority ? Icons.push_pin : Icons.push_pin_outlined,
      tooltip: inPriority ? 'Remove from priority' : 'Priority — show in Next to try',
      onPressed: _isSaving ? null : () => _togglePriority(detail),
    );
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
              prompt: 'Your rating',
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

  Future<void> _showListsSheet(CatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
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
              decoration: const InputDecoration(labelText: 'List name'),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
      if (name == null || name.trim().isEmpty) {
        return;
      }
      await ref.read(customBoardgameListsControllerProvider).createList(username, name);
      ref.invalidate(customBoardgameListsProvider);
    }

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final listsAsync = ref.watch(customBoardgameListsProvider);
            return GameListsSheet(
              detail: detail,
              listsAsync: listsAsync,
              isBuiltInList: BuiltInBoardgameLists.isBuiltIn,
              itemLabel: 'board games',
              onCreateList: createList,
              onToggleList: (list) async {
                await ref.read(customBoardgameListsControllerProvider).toggleItem(
                      username: username,
                      listId: list.id,
                      item: detail.media,
                    );
                ref.invalidate(customBoardgameListsProvider);
              },
              onDone: () => Navigator.pop(context),
            );
          },
        );
      },
    );
  }

  Future<void> _copyPrimaryLink(CatalogDetail detail) async {
    final primaryUrl = detail.links.isNotEmpty
        ? detail.links.first.url
        : 'https://boardgamegeek.com/boardgame/${detail.media.externalId}';
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
    final theme = Theme.of(context);

    return Scaffold(
      extendBody: true,
      appBar: const CulturAppBar(),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(catalogDetailProvider(_request)),
        ),
        data: (detail) {
          final overview = (detail.overview ?? '').trim();
          final tracking = detail.tracking;
          final scheme = theme.colorScheme;
          final collected = hasTrackingFlag(tracking, kCollectedTrackingFlag);
          return ListView(
            padding: const EdgeInsets.only(bottom: 132),
            children: [
              GameHeroCarousel(
                detail: detail,
                overlayActions: _heroPriorityPin(detail),
                onShareTap: () => _copyPrimaryLink(detail),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (detail.ratings.isNotEmpty) ...[
                      GameRatingsRow(ratings: detail.ratings),
                      const SizedBox(height: 12),
                    ],
                    BoardgameActionRow(
                      isSaving: _isSaving,
                      isInLater: trackingIsInWatchlist(tracking),
                      isBuy: trackingIsBuy(tracking),
                      isOwned: collected,
                      rating: tracking?.score,
                      onLaterTap: () => _runTrackingMutation(
                        mutation: (controller, username) => controller.toggleWatchlist(
                          username: username,
                          media: detail.media,
                          tracking: tracking,
                        ),
                      ),
                      onBuyTap: () => _runTrackingMutation(
                        mutation: (controller, username) => controller.toggleBuy(
                          username: username,
                          media: detail.media,
                          tracking: tracking,
                        ),
                      ),
                      onOwnedTap: () => _runTrackingMutation(
                        mutation: (controller, username) => runCollectedToggle(
                          context: context,
                          controller: controller,
                          username: username,
                          media: detail.media,
                          tracking: tracking,
                        ),
                      ),
                      onRateTap: () => _showRatingSheet(detail),
                      onListsTap: () => _showListsSheet(detail),
                    ),
                    if (overview.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text('Overview', style: CulturCatalogTypography.sectionHeading(theme)),
                      const SizedBox(height: 8),
                      Text(
                        overview,
                        maxLines: _showFullOverview ? null : 6,
                        overflow: _showFullOverview ? null : TextOverflow.ellipsis,
                        style: CulturCatalogTypography.bodyText(theme, scheme),
                      ),
                      if (overview.length > 280)
                        TextButton(
                          onPressed: () => setState(() => _showFullOverview = !_showFullOverview),
                          child: Text(_showFullOverview ? 'Show less' : 'Read more'),
                        ),
                    ],
                    if (detail.links.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      MediaDetailLinksSection(
                        links: detail.links,
                        onOpenLink: (url) async {
                          final uri = Uri.tryParse(url);
                          if (uri != null) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: LibraryMediaScope.boardgame,
      ),
    );
  }
}
