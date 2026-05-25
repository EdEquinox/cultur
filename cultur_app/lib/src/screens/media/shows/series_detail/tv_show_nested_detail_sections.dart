import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/utils/person_route_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yamtrack/src/models/movie/movie_detail_metric.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/providers/catalog_shelf_providers.dart';
import 'package:yamtrack/src/providers/catalog_tracking_providers.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/models/movie/movie_detail_models.dart';
import 'package:yamtrack/src/models/rating_sheet_result.dart';
import 'package:yamtrack/src/providers/movie_detail_providers.dart';
import '../../../widgets/episode_watched_when_sheet.dart';
import '../../../widgets/mark_watched_sheet.dart';
import '../../../widgets/movie_action_row.dart';
import '../../../widgets/tv_series_action_row.dart';
import '../../../widgets/tv_lists_sheet.dart';
import 'package:yamtrack/src/utils/tv_series_watching_flow.dart';
import 'package:yamtrack/src/utils/tv_start_watching.dart';
import 'package:yamtrack/src/screens/widgets/tv_series_watching_progress_button.dart';
import '../../../widgets/media_people_section_header.dart';
import '../../../widgets/movie_person_card.dart';
import '../../../widgets/movie_rating_sheet.dart';
import '../../../widgets/tv_mark_watched_progress_sheet.dart';
import '../../../widgets/tv_next_episode_card.dart';
import 'package:yamtrack/src/models/tv/series_detail.dart';
import 'package:yamtrack/src/providers/tv_catalog_providers.dart';
import 'package:yamtrack/src/utils/collected_toggle_flow.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';


/// Collected, watchlist, watched, rate, lists — same behaviour as the main TV detail page.
class TvShowTrackingActionBar extends ConsumerStatefulWidget {
  const TvShowTrackingActionBar({
    super.key,
    required this.mediaId,
    required this.detail,
    this.onAfterTrackingMutation,
    this.watchScopeSeasonDetail,
    this.watchScopeEpisode,
    this.watchScopeSeasonNumber,
    this.watchScopeEpisodeUserRating,
  });

  final String mediaId;
  final MovieCatalogDetail detail;
  final VoidCallback? onAfterTrackingMutation;
  /// When set with [watchScopeSeasonNumber], **Watched** only updates episode marks in that season.
  final TvSeasonDetailData? watchScopeSeasonDetail;
  /// When set, **Watched** only toggles this single episode (uses [watchScopeSeasonDetail] + [watchScopeSeasonNumber]).
  final TvEpisodeCatalog? watchScopeEpisode;
  final int? watchScopeSeasonNumber;
  /// Prefer over [watchScopeEpisode.userRating] when set (e.g. from episode catalog detail).
  final double? watchScopeEpisodeUserRating;

  @override
  ConsumerState<TvShowTrackingActionBar> createState() => _TvShowTrackingActionBarState();
}

class _TvShowTrackingActionBarState extends ConsumerState<TvShowTrackingActionBar> {
  bool _isSaving = false;

  void _invalidateShow(String username) {
    ref.invalidate(
      movieDetailProvider(
        MovieDetailRequest(mediaId: widget.mediaId, username: username, isTv: true),
      ),
    );
    ref.invalidate(tvWatchedEpisodesLibraryProvider);
    ref.invalidate(tvHomeShelvesProvider(username));
    ref.invalidate(tvSearchTrackingProvider(username));
  }

  Future<void> _runTrackingMutation({
    required Future<String?> Function(TrackingMutationController controller, String username) mutation,
  }) async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
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
      _invalidateShow(username);
      ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId));
      widget.onAfterTrackingMutation?.call();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      showApiErrorSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  double? _displayRatingForActionBar(MovieCatalogDetail d) {
    final epScope = widget.watchScopeEpisode;
    final seasonDetail = widget.watchScopeSeasonDetail;
    final seasonNum = widget.watchScopeSeasonNumber;
    final isEpisodeScope = epScope != null && seasonDetail != null && seasonNum != null;
    final isSeasonScope = !isEpisodeScope && seasonDetail != null && seasonNum != null;
    var display = d.tracking?.score;
    if (isEpisodeScope) {
      display = widget.watchScopeEpisodeUserRating ?? epScope.userRating ?? display;
    } else if (isSeasonScope) {
      display = seasonDetail.userSeasonRating ?? display;
    }
    return display;
  }

  Future<void> _showRatingSheet() async {
    final detail = widget.detail;
    final current = _displayRatingForActionBar(detail) ?? detail.tracking?.score;
    final hasExisting = current != null && current > 0;
    var stars = (current ?? 7).round().clamp(0, 10);
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<RatingSheetResult>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return MovieRatingSheet(
              title: 'Rate',
              prompt: 'Your rating (1–10)',
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
    if (!mounted) {
      return;
    }
    switch (result) {
      case null:
      case RatingSheetDismissed():
        return;
      case RatingSheetRemoved():
        await _runTrackingMutation(
          mutation: (c, u) => c.saveRating(
            username: u,
            media: detail.media,
            tracking: detail.tracking,
            remove: true,
          ),
        );
      case RatingSheetSet(:final score):
        await _runTrackingMutation(
          mutation: (c, u) => c.saveRating(
            username: u,
            media: detail.media,
            tracking: detail.tracking,
            score: score,
          ),
        );
    }
  }

  Future<void> _showWatchedSheet() async {
    final detail = widget.detail;
    final epScope = widget.watchScopeEpisode;
    final seasonDetail = widget.watchScopeSeasonDetail;
    final seasonNum = widget.watchScopeSeasonNumber;
    final isEpisodeScope = epScope != null && seasonDetail != null && seasonNum != null;
    final isSeasonScope = !isEpisodeScope && seasonDetail != null && seasonNum != null;

    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to update tracking.')),
      );
      return;
    }

    final theme = Theme.of(context);

    if (isEpisodeScope) {
      final ep = epScope;
      final sd = seasonDetail;
      final sn = seasonNum;
      final watched = sd.episodeIsWatched(ep.episodeNumber);
      if (watched) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unwatch episode'),
            content: Text('Remove watched status for S$sn E${ep.episodeNumber}?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unwatch')),
            ],
          ),
        );
        if (ok != true || !mounted) {
          return;
        }
        setState(() => _isSaving = true);
        try {
          await ref.read(episodeWatchMutationControllerProvider).putEpisodeWatched(
                username: username,
                mediaId: widget.mediaId,
                seasonNumber: sn,
                episodeNumber: ep.episodeNumber,
                watched: false,
              );
          _invalidateShow(username);
          ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId));
          widget.onAfterTrackingMutation?.call();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Episode unmarked.')));
          }
        } catch (error) {
          if (!mounted) {
            return;
          }
          showApiErrorSnackBar(context, error);
        } finally {
          if (mounted) {
            setState(() => _isSaving = false);
          }
        }
        return;
      }

      final when = await showEpisodeWatchedAtSheet(
        context,
        title: 'Mark as watched',
        subtitle: 'S$sn E${ep.episodeNumber} · ${ep.name}',
        backgroundColor: theme.colorScheme.surfaceContainerLow,
      );
      if (!mounted || when == null) {
        return;
      }
      setState(() => _isSaving = true);
      try {
        await ref.read(episodeWatchMutationControllerProvider).putEpisodeWatched(
              username: username,
              mediaId: widget.mediaId,
              seasonNumber: sn,
              episodeNumber: ep.episodeNumber,
              watched: true,
              watchedAtUtc: when.watchedAtUtc,
            );
        _invalidateShow(username);
        ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId));
        widget.onAfterTrackingMutation?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Episode marked watched.')));
        }
      } catch (error) {
        if (!mounted) {
          return;
        }
        showApiErrorSnackBar(context, error);
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
      return;
    }

    if (isSeasonScope) {
      final sd = seasonDetail;
      final sn = seasonNum;
      if (sd.seasonFullyWatched) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reset season progress'),
            content: Text('Remove all watched marks for Season $sn? Other seasons stay unchanged.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
            ],
          ),
        );
        if (ok != true || !mounted) {
          return;
        }
        setState(() => _isSaving = true);
        try {
          await ref.read(episodeWatchMutationControllerProvider).clearSeasonEpisodeWatches(
                username: username,
                mediaId: widget.mediaId,
                seasonNumber: sn,
              );
          _invalidateShow(username);
          ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId));
          widget.onAfterTrackingMutation?.call();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Season watch marks cleared.')));
          }
        } catch (error) {
          if (!mounted) {
            return;
          }
          showApiErrorSnackBar(context, error);
        } finally {
          if (mounted) {
            setState(() => _isSaving = false);
          }
        }
        return;
      }

      final result = await showModalBottomSheet<TvMarkWatchedProgressResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        builder: (sheetContext) {
          final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: TvMarkWatchedProgressSheet(
              mediaId: widget.mediaId,
              username: username,
              detail: detail,
              lockedSeasonNumber: sn,
            ),
          );
        },
      );
      if (result == null || !mounted) {
        return;
      }

      setState(() => _isSaving = true);
      try {
        await ref.read(episodeWatchMutationControllerProvider).markEpisodesWatchedThrough(
              username: username,
              mediaId: widget.mediaId,
              throughSeasonNumber: result.throughSeasonNumber,
              throughEpisodeNumber: result.throughEpisodeNumber,
              watchedAtUtc: result.watchedAtUtc,
              onlySeasonNumber: result.onlySeasonNumber ?? sn,
            );
        _invalidateShow(username);
        ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId));
        widget.onAfterTrackingMutation?.call();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Progress saved through S${result.throughSeasonNumber} '
              'E${result.throughEpisodeNumber} in this season.',
            ),
          ),
        );
      } catch (error) {
        showApiErrorSnackBar(context, error);
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
      return;
    }

    final watched = trackingIsWatched(detail.tracking);

    if (watched) {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        builder: (context) => RemoveWatchedSheet(detail: detail),
      );
      if (confirmed != true || !mounted) {
        return;
      }
      await _runTrackingMutation(
        mutation: (c, u) => c.toggleWatched(
          username: u,
          media: detail.media,
          tracking: detail.tracking,
        ),
      );
      return;
    }

    final result = await showModalBottomSheet<TvMarkWatchedProgressResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: TvMarkWatchedProgressSheet(
            mediaId: widget.mediaId,
            username: username,
            detail: detail,
          ),
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(episodeWatchMutationControllerProvider).markEpisodesWatchedThrough(
            username: username,
            mediaId: widget.mediaId,
            throughSeasonNumber: result.throughSeasonNumber,
            throughEpisodeNumber: result.throughEpisodeNumber,
            watchedAtUtc: result.watchedAtUtc,
            onlySeasonNumber: result.onlySeasonNumber,
          );
      ref.invalidate(movieDetailProvider(
        MovieDetailRequest(mediaId: widget.mediaId, username: username, isTv: true),
      ));
      ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId));
      widget.onAfterTrackingMutation?.call();
      final updated = await ref.read(
        movieDetailProvider(
          MovieDetailRequest(mediaId: widget.mediaId, username: username, isTv: true),
        ).future,
      );
      var message =
          'Progress saved through S${result.throughSeasonNumber} '
          'E${result.throughEpisodeNumber}.';
      if (trackingCanMarkTvAsWatched(updated.tracking)) {
        final finishedMsg = await ref.read(trackingMutationControllerProvider).markAsWatched(
              username: username,
              media: detail.media,
              tracking: updated.tracking,
              completedAtUtc: result.watchedAtUtc,
              score: result.score,
            );
        if (finishedMsg.contains('finished')) {
          message = finishedMsg;
        } else {
          message = '$message $finishedMsg';
        }
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      showApiErrorSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _startWatchingTv(MovieCatalogDetail detail) async {
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

    if (tvSeriesHasEpisodeProgress(detail.tracking)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already started — check Continue watching on TV home.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await startTvSeriesFromFirstEpisode(
        episodes: ref.read(episodeWatchMutationControllerProvider),
        tracking: ref.read(trackingMutationControllerProvider),
        username: username,
        media: detail.media,
        trackingItem: detail.tracking,
      );
      _invalidateShow(username);
      ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Episode 1 marked — find the next episode under Continue watching.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showApiErrorSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showListsSheet() async {
    final detail = widget.detail;
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to manage lists.')),
      );
      return;
    }

    final epScope = widget.watchScopeEpisode;
    final seasonDetail = widget.watchScopeSeasonDetail;
    final seasonNum = widget.watchScopeSeasonNumber;
    final isEpisodeScope = epScope != null && seasonDetail != null && seasonNum != null;
    final isSeasonScope = !isEpisodeScope && seasonDetail != null && seasonNum != null;

    final int? scopeSeason;
    final int? scopeEpisode;
    if (isEpisodeScope) {
      scopeSeason = seasonNum;
      scopeEpisode = epScope.episodeNumber;
    } else if (isSeasonScope) {
      scopeSeason = seasonNum;
      scopeEpisode = null;
    } else {
      scopeSeason = null;
      scopeEpisode = null;
    }

    final scopedItem = TvCustomListItem(
      show: detail.media,
      seasonNumber: scopeSeason,
      episodeNumber: scopeEpisode,
    );

    Future<void> createList() async {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Create TV list'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'List name',
                hintText: 'Favorites, Rewatch picks…',
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
      final list = await ref.read(customTvListsControllerProvider).createList(
            username,
            name.trim(),
          );
      await ref.read(customTvListsControllerProvider).toggleItem(
            username: username,
            listId: list.id,
            item: scopedItem,
          );
      ref.invalidate(customTvListsProvider);
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final listsAsync = ref.watch(customTvListsProvider);
            return TvListsSheet(
              show: detail.media,
              listsAsync: listsAsync,
              seasonNumber: scopeSeason,
              episodeNumber: scopeEpisode,
              onCreateList: () async {
                await createList();
                ref.invalidate(customTvListsProvider);
              },
              onToggleList: (list) async {
                await ref.read(customTvListsControllerProvider).toggleItem(
                      username: username,
                      listId: list.id,
                      item: scopedItem,
                    );
                ref.invalidate(customTvListsProvider);
              },
              onDone: () => Navigator.of(context).pop(),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final collected = hasTrackingFlag(d.tracking, kCollectedTrackingFlag);
    final watchlist = trackingIsInWatchlist(d.tracking);
    final buy = trackingIsBuy(d.tracking);
    final rating = _displayRatingForActionBar(d);

    final epScope = widget.watchScopeEpisode;
    final seasonDetail = widget.watchScopeSeasonDetail;
    final seasonNum = widget.watchScopeSeasonNumber;
    final isEpisodeScope = epScope != null && seasonDetail != null && seasonNum != null;
    final isSeasonScope = !isEpisodeScope && seasonDetail != null && seasonNum != null;

    final bool watchedFlag;
    if (isEpisodeScope) {
      watchedFlag = seasonDetail.episodeIsWatched(epScope.episodeNumber);
    } else if (isSeasonScope) {
      watchedFlag = seasonDetail.seasonFullyWatched;
    } else {
      watchedFlag = trackingIsWatched(d.tracking);
    }

    final tracking = d.tracking;
    final isSeriesScope = !isEpisodeScope && !isSeasonScope;
    final activelyWatching =
        isSeriesScope && tvSeriesIsActivelyWatching(tracking: tracking, detail: d);
    final seriesFinished =
        isSeriesScope && tvSeriesWatchingTileShowsFinished(tracking: tracking, detail: d);
    final dropped = isSeriesScope && trackingIsDropped(tracking);
    final progressLabel =
        isSeriesScope ? tvSeriesEpisodeProgressLabel(tracking: tracking, detail: d) : null;

    if (isSeriesScope) {
      return TvSeriesActionRow(
        isSaving: _isSaving,
        isCollected: collected,
        isInWatchlist: watchlist,
        isWatching: activelyWatching,
        isSeriesFinished: seriesFinished,
        isDropped: dropped,
        isBuy: buy,
        rating: rating,
        watchingProgressLabel: progressLabel,
        onCollectedTap: () => _runTrackingMutation(
          mutation: (c, u) => runCollectedToggle(
            context: context,
            controller: c,
            username: u,
            media: d.media,
            tracking: tracking,
          ),
        ),
        onWatchlistTap: () => _runTrackingMutation(
          mutation: (c, u) => c.toggleWatchlist(
            username: u,
            media: d.media,
            tracking: tracking,
          ),
        ),
        onWatchingTap: () => handleTvSeriesWatchingTap(
          context: context,
          detail: d,
          runTrackingMutation: (mutation) => _runTrackingMutation(mutation: mutation),
          startWatchingTv: () => _startWatchingTv(d),
        ),
        onBuyTap: () => _runTrackingMutation(
          mutation: (c, u) => c.toggleBuy(
            username: u,
            media: d.media,
            tracking: tracking,
          ),
        ),
        onRateTap: _showRatingSheet,
        onListsTap: _showListsSheet,
      );
    }

    return MovieActionRow(
      isSaving: _isSaving,
      isCollected: collected,
      isInWatchlist: watchlist,
      isWatched: watchedFlag,
      isBuy: buy,
      rating: rating,
      isTv: true,
      onCollectedTap: () => _runTrackingMutation(
        mutation: (c, u) => runCollectedToggle(
          context: context,
          controller: c,
          username: u,
          media: d.media,
          tracking: tracking,
        ),
      ),
      onWatchlistTap: () => _runTrackingMutation(
        mutation: (c, u) => c.toggleWatchlist(
          username: u,
          media: d.media,
          tracking: tracking,
        ),
      ),
      onWatchedTap: _showWatchedSheet,
      onBuyTap: () => _runTrackingMutation(
        mutation: (c, u) => c.toggleBuy(
          username: u,
          media: d.media,
          tracking: tracking,
        ),
      ),
      onRateTap: _showRatingSheet,
      onListsTap: _showListsSheet,
    );
  }
}

class TvShowNextEpisodeStrip extends StatelessWidget {
  const TvShowNextEpisodeStrip({
    super.key,
    required this.mediaId,
    required this.detail,
  });

  final String mediaId;
  final MovieCatalogDetail detail;

  @override
  Widget build(BuildContext context) {
    final card = detail.nextEpisodeCard;
    if (card == null) {
      return const SizedBox.shrink();
    }
    return TvNextEpisodeCard(
      mediaId: mediaId,
      data: card,
      isWatched: detail.episodeIsWatched(card.seasonNumber, card.episodeNumber),
    );
  }
}

class TvShowCastPreviewStrip extends StatelessWidget {
  const TvShowCastPreviewStrip({
    super.key,
    required this.detail,
    required this.mediaId,
    this.additionalPeople = const [],
    this.castBase,
    this.viewAllCastPath,
  });

  final MovieCatalogDetail detail;
  final String mediaId;
  final List<MovieDetailPerson> additionalPeople;
  /// When set, replaces [detail.cast] as the primary list (e.g. season- or episode-level credits).
  final List<MovieDetailPerson>? castBase;
  /// When set, **View all** navigates here (e.g. season or episode cast list). Defaults to whole-show cast.
  final String? viewAllCastPath;

  static const int _previewCount = 8;

  void _openPerson(BuildContext context, MovieDetailPerson person) {
    final id = person.personId;
    if (id == null || id.isEmpty) {
      return;
    }
    context.push(personAppRoutePath(id));
  }

  @override
  Widget build(BuildContext context) {
    final primary = castBase ?? detail.cast;
    final merged = mergeCreditPeopleLists(primary, additionalPeople);
    if (merged.isEmpty) {
      return const SizedBox.shrink();
    }
    final preview = merged.take(_previewCount).toList();
    final hasMore = merged.length > preview.length;
    final defaultCastPath = '/tv/$mediaId/cast';
    final resolvedViewAllPath = viewAllCastPath ?? defaultCastPath;
    final useContextCastList =
        viewAllCastPath != null && viewAllCastPath != defaultCastPath;
    final showViewAll = hasMore || useContextCastList;
    final sectionTitle = additionalPeople.isEmpty ? 'Cast' : 'Cast & guest stars';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MediaPeopleSectionHeader(
          title: sectionTitle,
          onSeeAll: showViewAll ? () => context.push(resolvedViewAllPath) : null,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: MoviePersonCard.shelfExtent,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: preview.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final person = preview[index];
              final canOpen = person.personId != null && person.personId!.isNotEmpty;
              return Align(
                alignment: Alignment.topLeft,
                child: MoviePersonCard(
                  person: person,
                  onTap: canOpen ? () => _openPerson(context, person) : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class TvShowRatingsStrip extends StatelessWidget {
  const TvShowRatingsStrip({super.key, required this.ratings});

  final List<MovieDetailMetric> ratings;

  @override
  Widget build(BuildContext context) {
    if (ratings.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ratings', style: CulturCatalogTypography.sectionHeading(theme)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final r in ratings) ...[
                _RatingMiniChip(metric: r, scheme: scheme, theme: theme),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RatingMiniChip extends StatelessWidget {
  const _RatingMiniChip({
    required this.metric,
    required this.scheme,
    required this.theme,
  });

  final MovieDetailMetric metric;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final v = metric.value.trim();
    final isLink = v.startsWith('http://') || v.startsWith('https://');
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            metric.label,
            style: CulturCatalogTypography.listMeta(theme, scheme),
          ),
          const SizedBox(height: 4),
          Text(
            metric.value,
            style: CulturCatalogTypography.listTitle(theme),
          ),
        ],
      ),
    );

    final box = Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(4),
      child: isLink
          ? InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final uri = Uri.tryParse(v);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: child,
            )
          : child,
    );
    return box;
  }
}
