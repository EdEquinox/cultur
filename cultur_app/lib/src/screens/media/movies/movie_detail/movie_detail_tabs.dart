part of 'movie_detail_page.dart';

class _MovieDetailsTab extends StatelessWidget {
  const _MovieDetailsTab({
    super.key,
    required this.detail,
    required this.isSaving,
    required this.showFullOverview,
    required this.onToggleOverview,
    required this.onCollectedToggle,
    required this.onWatchlistToggle,
    required this.onWatchedToggle,
    required this.onBuyToggle,
    required this.onRateTap,
    required this.onListsTap,
    required this.onOpenVideo,
    required this.onOpenRecommendation,
    required this.onShareTap,
    required     this.onOpenLink,
    this.onWatchingTap,
    this.onResolvePending,
    this.isTv = false,
    this.mediaId,
    this.heroOverlayActions,
  });

  final MovieCatalogDetail detail;
  final bool isSaving;
  final bool showFullOverview;
  final VoidCallback onToggleOverview;
  final VoidCallback onCollectedToggle;
  final VoidCallback onWatchlistToggle;
  final VoidCallback onWatchedToggle;
  final VoidCallback onBuyToggle;
  final VoidCallback onRateTap;
  final VoidCallback onListsTap;
  final ValueChanged<String> onOpenVideo;
  final ValueChanged<CatalogItem> onOpenRecommendation;
  final VoidCallback onShareTap;
  final ValueChanged<String> onOpenLink;
  final VoidCallback? onWatchingTap;
  final VoidCallback? onResolvePending;
  final bool isTv;
  final String? mediaId;
  final Widget? heroOverlayActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overview = detail.overview?.trim() ?? '';
    final collected = hasTrackingFlag(detail.tracking, kCollectedTrackingFlag);
    final watchlist = trackingIsInWatchlist(detail.tracking);
    final watched = trackingIsWatched(detail.tracking);
    final buy = trackingIsBuy(detail.tracking);
    final rating = detail.tracking?.score;
    final tracking = detail.tracking;
    final activelyWatching =
        isTv && tvSeriesIsActivelyWatching(tracking: tracking, detail: detail);
    final seriesFinished =
        isTv && tvSeriesWatchingTileShowsFinished(tracking: tracking, detail: detail);
    final dropped = isTv && trackingIsDropped(tracking);
    final progressLabel =
        isTv ? tvSeriesEpisodeProgressLabel(tracking: tracking, detail: detail) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MovieHeroCarousel(
          detail: detail,
          isTv: isTv,
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
        if (isTv && onWatchingTap != null)
          TvSeriesActionRow(
            isSaving: isSaving,
            isCollected: collected,
            isInWatchlist: watchlist,
            isWatching: activelyWatching,
            isSeriesFinished: seriesFinished,
            isDropped: dropped,
            isBuy: buy,
            rating: rating,
            watchingProgressLabel: progressLabel,
            onCollectedTap: onCollectedToggle,
            onWatchlistTap: onWatchlistToggle,
            onWatchingTap: onWatchingTap!,
            onBuyTap: onBuyToggle,
            onRateTap: onRateTap,
            onListsTap: onListsTap,
          )
        else
          MovieActionRow(
            isSaving: isSaving,
            isCollected: collected,
            isInWatchlist: watchlist,
            isWatched: watched,
            isBuy: buy,
            rating: rating,
            isTv: isTv,
            tvStartWatchingMode:
                isTv && detail.watchedEpisodes.isEmpty && !trackingIsWatched(detail.tracking),
            onCollectedTap: onCollectedToggle,
            onWatchlistTap: onWatchlistToggle,
            onWatchedTap: onWatchedToggle,
            onBuyTap: onBuyToggle,
            onRateTap: onRateTap,
            onListsTap: onListsTap,
          ),
        if (isTv &&
            mediaId != null &&
            mediaId!.isNotEmpty &&
            detail.nextEpisodeCard != null) ...[
          const SizedBox(height: 12),
          TvNextEpisodeCard(
            mediaId: mediaId!,
            data: detail.nextEpisodeCard!,
            isWatched: detail.episodeIsWatched(
              detail.nextEpisodeCard!.seasonNumber,
              detail.nextEpisodeCard!.episodeNumber,
            ),
          ),
        ],
        if (overview.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    overview,
                    maxLines: showFullOverview ? null : 4,
                    overflow:
                        showFullOverview ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: CulturCatalogTypography.bodyText(theme, scheme),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onToggleOverview,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      showFullOverview ? 'Show less' : 'View more',
                      style: CulturCatalogTypography.linkAction(theme, scheme),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (detail.videos.isNotEmpty) ...[
          const SizedBox(height: 16),
          MovieVideoShelf(
            videos: detail.videos,
            onOpenVideo: onOpenVideo,
          ),
        ],
        if (detail.genres.isNotEmpty || detail.keywords.isNotEmpty) ...[
          const SizedBox(height: 16),
          GenresTagsCard(
            genres: detail.genres,
            keywords: detail.keywords,
          ),
        ],
        if (detail.recommendations.isNotEmpty) ...[
          const SizedBox(height: 16),
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

class _TvSeasonsTab extends ConsumerWidget {
  const _TvSeasonsTab({
    super.key,
    required this.mediaId,
    required this.watchedEpisodes,
    required this.onMarkWatched,
  });

  final String mediaId;
  final List<WatchedEpisode> watchedEpisodes;
  final VoidCallback onMarkWatched;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tvSeasonListCatalogProvider(mediaId));
    final theme = Theme.of(context);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(tvSeasonListCatalogProvider(mediaId)),
      ),
      data: (data) {
        if (data.items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No seasons listed for this series.',
                style: CulturCatalogTypography.emptyState(theme, theme.colorScheme),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: onMarkWatched,
              icon: const Icon(Icons.remove_red_eye_outlined),
              label: const Text('Watched…'),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: data.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final s = data.items[index];
                final progress = tvSeasonListWatchProgressLabel(
                  watchedEpisodes: watchedEpisodes,
                  seasonNumber: s.seasonNumber,
                  episodeCount: s.episodeCount,
                );
                final subtitleParts = <String>[
                  ?progress,
                  '${s.episodeCount} episode${s.episodeCount == 1 ? '' : 's'}',
                  if (s.airDate != null && s.airDate!.trim().isNotEmpty) s.airDate!,
                ];
                return ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  tileColor: theme.colorScheme.surfaceContainerLow,
                  leading: _SeasonListLeading(url: s.posterUrl),
                  title: Text(s.name, style: CulturCatalogTypography.listTitle(theme)),
                  subtitle: Text(
                    subtitleParts.join(' · '),
                    style: CulturCatalogTypography.listMeta(theme, theme.colorScheme),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/tv/$mediaId/seasons/${s.seasonNumber}'),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _SeasonListLeading extends StatelessWidget {
  const _SeasonListLeading({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    if (url != null && url!.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url!,
          width: size,
          height: size * 1.45,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _placeholder(context, size),
        ),
      );
    }
    return _placeholder(context, size);
  }

  Widget _placeholder(BuildContext context, double size) {
    return Container(
      width: size,
      height: size * 1.2,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.movie_filter_outlined, color: Theme.of(context).colorScheme.outline),
    );
  }
}

class _MoviePeopleTab extends StatelessWidget {
  const _MoviePeopleTab({required this.detail, required this.isTv, super.key});

  final MovieCatalogDetail detail;
  final bool isTv;

  static const int _castPreviewCount = 12;

  void _tryOpenPerson(BuildContext context, MovieDetailPerson person) {
    final id = person.personId;
    if (id == null || id.isEmpty) {
      return;
    }
    context.push(personAppRoutePath(id));
  }

  @override
  Widget build(BuildContext context) {
    final cast = detail.cast;
    final previewCast = cast.take(_castPreviewCount).toList();
    final movieMediaId = detail.media.id;
    final castPath = isTv ? '/tv/$movieMediaId/cast' : '/movies/$movieMediaId/cast';
    final crewPath = isTv ? '/tv/$movieMediaId/crew' : '/movies/$movieMediaId/crew';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cast.isNotEmpty) ...[
          MediaPeopleSectionHeader(
            title: 'Cast',
            onSeeAll: cast.isNotEmpty ? () => context.push(castPath) : null,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: MoviePersonCard.shelfExtent,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: previewCast.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final person = previewCast[index];
                final canOpen = person.personId != null && person.personId!.isNotEmpty;
                return Align(
                  alignment: Alignment.topLeft,
                  child: MoviePersonCard(
                    person: person,
                    onTap: canOpen ? () => _tryOpenPerson(context, person) : null,
                  ),
                );
              },
            ),
          ),
        ],
        if (detail.crew.isNotEmpty) ...[
          SizedBox(height: cast.isNotEmpty ? 28 : 0),
          MediaPeopleSectionHeader(
            title: 'Crew',
            onSeeAll: () => context.push(crewPath),
          ),
          const SizedBox(height: 16),
          _PeopleTabCrewPanel(
            crew: detail.crew,
            onPersonTap: (person) => _tryOpenPerson(context, person),
          ),
        ],
      ],
    );
  }
}

class _PeopleTabCrewPanel extends StatelessWidget {
  const _PeopleTabCrewPanel({
    required this.crew,
    required this.onPersonTap,
  });

  final List<MovieDetailCrewGroup> crew;
  final ValueChanged<MovieDetailPerson> onPersonTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.culturTokens;
    final shelfBg = tokens.shelfRowBackground;
    final r = tokens.radiusTight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: shelfBg,
        borderRadius: BorderRadius.circular(r + 4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < crew.length; i++) ...[
              MediaCrewDepartmentSection(
                group: crew[i],
                onPersonTap: onPersonTap,
              ),
              if (i < crew.length - 1) const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}
