import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/utils/person_route_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/providers/catalog_shelf_providers.dart';
import 'package:yamtrack/src/providers/catalog_tracking_providers.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/providers/tv_catalog_providers.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/providers/movie_detail_providers.dart';
import 'package:yamtrack/src/screens/widgets/tv_next_episode_card.dart';
import 'package:yamtrack/src/screens/widgets/genres_tags_card.dart';
import 'package:yamtrack/src/screens/widgets/mark_watched_sheet.dart';
import 'package:yamtrack/src/screens/widgets/tv_mark_watched_progress_sheet.dart';
import 'package:yamtrack/src/screens/widgets/movie_action_row.dart';
import 'package:yamtrack/src/screens/widgets/tv_series_action_row.dart';
import 'package:yamtrack/src/screens/widgets/tv_series_watching_progress_button.dart';
import 'package:yamtrack/src/utils/tv_series_watching_flow.dart';
import 'package:yamtrack/src/screens/widgets/media_crew_department_section.dart';
import 'package:yamtrack/src/screens/widgets/media_people_section_header.dart';
import 'package:yamtrack/src/screens/widgets/movie_hero_carousel.dart';
import 'package:yamtrack/src/screens/widgets/movie_lists_sheet.dart';
import 'package:yamtrack/src/screens/widgets/movie_person_card.dart';
import 'package:yamtrack/src/models/rating_sheet_result.dart';
import 'package:yamtrack/src/screens/widgets/movie_rating_sheet.dart';
import 'package:yamtrack/src/screens/widgets/movie_recommendation_shelf.dart';
import 'package:yamtrack/src/screens/widgets/movie_tab_bar.dart';
import 'package:yamtrack/src/screens/widgets/movie_video_shelf.dart';
import 'package:yamtrack/src/screens/widgets/media_detail_links_section.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

import 'package:yamtrack/src/models/movie/movie_catalog_detail.dart';
import 'package:yamtrack/src/models/tv/series_detail.dart';
import 'package:yamtrack/src/utils/tv_start_watching.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/models/movie/movie_detail_crew_group.dart';
import 'package:yamtrack/src/utils/library_utils.dart';
import 'package:yamtrack/src/utils/collected_toggle_flow.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_pending_catalog_banner.dart';
import 'package:yamtrack/src/screens/widgets/catalog_resolve_pending_sheet.dart';
import 'package:yamtrack/src/providers/pending_imports_providers.dart';

part 'movie_detail_page_actions.dart';
part 'movie_detail_tabs.dart';

class MovieDetailPage extends ConsumerStatefulWidget {
  const MovieDetailPage({required this.mediaId, this.isTv = false, super.key});

  final String mediaId;
  final bool isTv;

  @override
  ConsumerState<MovieDetailPage> createState() => _MovieDetailPageState();
}

class _MovieDetailPageState extends ConsumerState<MovieDetailPage>
    with _MovieDetailPageActions {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    final request = MovieDetailRequest(
      mediaId: widget.mediaId,
      username: username,
      isTv: widget.isTv,
    );
    final detailAsync = ref.watch(movieDetailProvider(request));

    return Scaffold(
      appBar: const CulturAppBar(),
      extendBody: true,
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(movieDetailProvider(request)),
        ),
        data: (detail) {
          final tabContent = widget.isTv
              ? switch (_selectedTabIndex) {
                  2 => _MoviePeopleTab(
                    key: const ValueKey('people-tab'),
                    detail: detail,
                    isTv: widget.isTv,
                  ),
                  1 => _TvSeasonsTab(
                    key: const ValueKey('seasons-tab'),
                    mediaId: widget.mediaId,
                    watchedEpisodes: detail.watchedEpisodes,
                    onMarkWatched: _showTvWatchedProgressFromSeasonsTab,
                  ),
                  _ => _MovieDetailsTab(
                    key: const ValueKey('details-tab'),
                    detail: detail,
                    isSaving: _isSaving,
                    showFullOverview: _showFullOverview,
                    isTv: widget.isTv,
                    mediaId: widget.mediaId,
                    heroOverlayActions: _movieHeroOverlayActions(detail),
                    onToggleOverview: () {
                      setState(() {
                        _showFullOverview = !_showFullOverview;
                      });
                    },
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
                    onBuyToggle: () => _runTrackingMutation(
                      mutation: (controller, username) => controller.toggleBuy(
                        username: username,
                        media: detail.media,
                        tracking: detail.tracking,
                      ),
                    ),
                    onWatchedToggle: () {
                      if (detail.watchedEpisodes.isEmpty &&
                          !trackingIsWatched(detail.tracking)) {
                        _startWatchingTv(detail);
                      } else {
                        _showWatchedSheet(detail);
                      }
                    },
                    onRateTap: () => _showRatingSheet(detail),
                    onListsTap: () => _showListsSheet(detail),
                    onWatchingTap: () => handleTvSeriesWatchingTap(
                      context: context,
                      detail: detail,
                      runTrackingMutation: (mutation) =>
                          _runTrackingMutation(mutation: mutation),
                      startWatchingTv: () => _startWatchingTv(detail),
                    ),
                    onOpenVideo: _openExternalUrl,
                    onOpenRecommendation: (item) => context.push(
                      widget.isTv ? '/tv/${item.id}' : '/movies/${item.id}',
                    ),
                    onShareTap: () => _copyPrimaryLink(detail),
                    onOpenLink: _openExternalUrl,
                    onResolvePending: detail.catalogPending
                        ? () => _openResolvePendingSheet(detail)
                        : null,
                  ),
                }
              : switch (_selectedTabIndex) {
                  1 => _MoviePeopleTab(
                    key: const ValueKey('people-tab'),
                    detail: detail,
                    isTv: widget.isTv,
                  ),
                  _ => _MovieDetailsTab(
                    key: const ValueKey('details-tab'),
                    detail: detail,
                    isSaving: _isSaving,
                    showFullOverview: _showFullOverview,
                    isTv: widget.isTv,
                    mediaId: widget.mediaId,
                    heroOverlayActions: _movieHeroOverlayActions(detail),
                    onToggleOverview: () {
                      setState(() {
                        _showFullOverview = !_showFullOverview;
                      });
                    },
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
                    onBuyToggle: () => _runTrackingMutation(
                      mutation: (controller, username) => controller.toggleBuy(
                        username: username,
                        media: detail.media,
                        tracking: detail.tracking,
                      ),
                    ),
                    onWatchedToggle: () => _showWatchedSheet(detail),
                    onRateTap: () => _showRatingSheet(detail),
                    onListsTap: () => _showListsSheet(detail),
                    onOpenVideo: _openExternalUrl,
                    onOpenRecommendation: (item) => context.push(
                      widget.isTv ? '/tv/${item.id}' : '/movies/${item.id}',
                    ),
                    onShareTap: () => _copyPrimaryLink(detail),
                    onOpenLink: _openExternalUrl,
                    onResolvePending: detail.catalogPending
                        ? () => _openResolvePendingSheet(detail)
                        : null,
                  ),
                };

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              MovieTabBar(
                selectedIndex: _selectedTabIndex,
                tabs: widget.isTv
                    ? const ['Details', 'Seasons', 'People']
                    : const ['Details', 'People'],
                onSelected: (index) {
                  setState(() {
                    _selectedTabIndex = index;
                  });
                },
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                reverseDuration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      ...previousChildren,
                      ...switch (currentChild) {
                        final Widget child => [child],
                        null => const <Widget>[],
                      },
                    ],
                  );
                },
                transitionBuilder: (child, animation) {
                  final offsetAnimation = Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: offsetAnimation,
                      child: child,
                    ),
                  );
                },
                child: tabContent,
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: widget.isTv ? LibraryMediaScope.tv : LibraryMediaScope.movie,
      ),
    );
  }
}
