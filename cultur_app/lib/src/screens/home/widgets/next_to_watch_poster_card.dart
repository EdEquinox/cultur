import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/catalog_tracking_providers.dart';
import 'package:yamtrack/src/providers/next_to_watch_providers.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/screens/home/widgets/next_to_watch_corner_badge.dart';
import 'package:yamtrack/src/screens/widgets/mark_watched_sheet.dart';
import 'package:yamtrack/src/providers/catalog_shelf_providers.dart';
import 'package:yamtrack/src/providers/tv_catalog_providers.dart';
import 'package:yamtrack/src/providers/movie_detail_providers.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/tv_start_watching.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_image.dart';

/// Poster card for movie/TV "Next to watch" shelves with a primary tracking action.
class NextToWatchPosterCard extends ConsumerStatefulWidget {
  const NextToWatchPosterCard({
    required this.item,
    required this.username,
    super.key,
    this.onTap,
    this.inGrid = false,
  });

  static const double cardWidth = 144;
  static const double _gap = 6;
  static const double _gridGap = 4;
  static const double _buttonHeight = 32;
  static const double _gridButtonHeight = 30;
  static const double posterAspectRatio = 2 / 3;

  /// Poster height on the horizontal shelf (fixed width [cardWidth]).
  static const double _shelfPosterHeight = 168;

  /// Shelf row height — derived from [layoutHeight] at [cardWidth].
  static double get cardHeight => layoutHeight(
        width: cardWidth,
        inGrid: false,
        hasSubtitle: true,
      );

  /// Grid [childAspectRatio] for 3-column next-to-watch lists (~120px cells).
  static const double gridChildAspectRatio = 0.36;

  /// Total card height for poster + text + action button.
  static double layoutHeight({
    required double width,
    required bool inGrid,
    bool hasSubtitle = true,
  }) {
    final posterH = inGrid ? width / posterAspectRatio : _shelfPosterHeight;
    final gap = inGrid ? _gridGap : _gap;
    final titleH = inGrid ? 14.0 : 15.0;
    final subtitleH = hasSubtitle ? (inGrid ? 11.0 : 12.0) : 0.0;
    final subtitleGaps = hasSubtitle ? gap * 2 : 0.0;
    final buttonH = inGrid ? _gridButtonHeight : _buttonHeight;
    return posterH + gap + titleH + subtitleGaps + subtitleH + gap + buttonH + 8;
  }

  static double gridChildAspectRatioForWidth(double cellWidth, {bool hasSubtitle = true}) {
    final h = layoutHeight(width: cellWidth, inGrid: true, hasSubtitle: hasSubtitle);
    if (h <= 0) {
      return gridChildAspectRatio;
    }
    return cellWidth / h;
  }

  final NextToWatchShelfItem item;
  final String username;
  final VoidCallback? onTap;
  final bool inGrid;

  @override
  ConsumerState<NextToWatchPosterCard> createState() => _NextToWatchPosterCardState();
}

class _NextToWatchPosterCardState extends ConsumerState<NextToWatchPosterCard> {
  bool _busy = false;

  bool get _isTv => widget.item.media.mediaType == 'tv';

  TrackingItem? _tracking(Map<String, TrackingItem> byId) => byId[widget.item.media.id];

  Future<void> _runMutation(Future<String> Function(TrackingMutationController c) mutation) async {
    final username = widget.username.trim();
    if (username.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      final message = await mutation(ref.read(trackingMutationControllerProvider));
      invalidateNextToWatchCaches(
        ref,
        username: username,
        isTv: _isTv,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) {
        return;
      }
      showApiErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _onMovieWatched(TrackingItem? tracking) async {
    final media = widget.item.media;
    if (trackingIsWatched(tracking)) {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        builder: (context) => RemoveWatchedSheet.forCatalog(media: media),
      );
      if (confirmed != true || !mounted) {
        return;
      }
      await _runMutation(
        (c) => c.toggleWatched(
          username: widget.username,
          media: media,
          tracking: tracking,
        ),
      );
      return;
    }

    final result = await showModalBottomSheet<MarkWatchedSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: MarkWatchedSheet.forCatalog(media: media, tracking: tracking),
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }
    await _runMutation(
      (c) => c.markAsWatched(
        username: widget.username,
        media: media,
        tracking: tracking,
        completedAtUtc: result.completedAtUtc,
        score: result.score,
      ),
    );
  }

  Future<void> _onTvStart(TrackingItem? tracking) async {
    final media = widget.item.media;
    final username = widget.username.trim();
    if (username.isEmpty) {
      return;
    }

    if (tvSeriesHasEpisodeProgress(tracking)) {
      if (!mounted) {
        return;
      }
      context.push(catalogItemDetailPath(media));
      return;
    }

    setState(() => _busy = true);
    try {
      await startTvSeriesFromFirstEpisode(
        episodes: ref.read(episodeWatchMutationControllerProvider),
        tracking: ref.read(trackingMutationControllerProvider),
        username: username,
        media: media,
        trackingItem: tracking,
      );
      invalidateNextToWatchCaches(ref, username: username, isTv: true);
      ref.invalidate(tvHomeShelvesProvider(username));
      ref.invalidate(tvSearchTrackingProvider(username));
      ref.invalidate(tvSeasonListCatalogProvider(media.id));
      ref.invalidate(
        movieDetailProvider(
          MovieDetailRequest(mediaId: media.id, username: username, isTv: true),
        ),
      );
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
    } catch (e) {
      if (!mounted) {
        return;
      }
      showApiErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.culturTokens;
    final badgeBg = theme.colorScheme.tertiary.withValues(alpha: 0.92);
    final badgeFg = theme.colorScheme.onTertiary;
    final secondary = catalogItemDirectorOrSubtitle(widget.item.media);
    final hasSubtitle = secondary.isNotEmpty;
    final trackingAsync = _isTv
        ? ref.watch(tvSearchTrackingProvider(widget.username))
        : ref.watch(movieSearchTrackingProvider(widget.username));

    final tracking = trackingAsync.maybeWhen(
      data: (byId) => _tracking(byId),
      orElse: () => null,
    );
    final hasEpisodeProgress = tvSeriesHasEpisodeProgress(tracking);
    final isWatched = trackingIsWatched(tracking);

    final actionLabel = _isTv
        ? (hasEpisodeProgress ? 'Continue' : 'Start')
        : (isWatched ? 'Watched' : 'Watched');
    final actionIcon = _isTv
        ? (hasEpisodeProgress ? Icons.play_arrow_rounded : Icons.play_circle_outline)
        : (isWatched ? Icons.check_circle : Icons.remove_red_eye_outlined);

    final poster = ClipRRect(
      borderRadius: tokens.borderRadiusTight,
      child: InkWell(
        borderRadius: tokens.borderRadiusTight,
        onTap: widget.onTap,
        child: widget.inGrid
            ? AspectRatio(
                aspectRatio: NextToWatchPosterCard.posterAspectRatio,
                child: posterStack(tokens, badgeBg, badgeFg),
              )
            : SizedBox(
                width: NextToWatchPosterCard.cardWidth,
                height: NextToWatchPosterCard._shelfPosterHeight,
                child: posterStack(tokens, badgeBg, badgeFg),
              ),
      ),
    );

    final titleBlock = InkWell(
      borderRadius: tokens.borderRadiusTight,
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.item.media.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CulturCatalogTypography.gridTitle(theme),
          ),
          if (hasSubtitle) ...[
            SizedBox(height: widget.inGrid ? 2 : 4),
            Text(
              secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CulturCatalogTypography.gridSubtitle(theme, theme.colorScheme),
            ),
          ],
        ],
      ),
    );

    final actionButton = FilledButton.tonalIcon(
      onPressed: _busy || widget.username.trim().isEmpty
          ? null
          : () {
              if (_isTv) {
                _onTvStart(tracking);
              } else {
                _onMovieWatched(tracking);
              }
            },
      icon: _busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            )
          : Icon(actionIcon, size: widget.inGrid ? 16 : 18),
      label: Text(actionLabel, style: CulturCatalogTypography.gridTitle(theme)),
      style: FilledButton.styleFrom(
        minimumSize: Size.fromHeight(
          widget.inGrid ? NextToWatchPosterCard._gridButtonHeight : NextToWatchPosterCard._buttonHeight,
        ),
        padding: EdgeInsets.symmetric(horizontal: widget.inGrid ? 6 : 8, vertical: 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );

    final gap = widget.inGrid ? NextToWatchPosterCard._gridGap : NextToWatchPosterCard._gap;

    if (widget.inGrid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          poster,
          SizedBox(height: gap),
          titleBlock,
          SizedBox(height: gap),
          actionButton,
        ],
      );
    }

    return SizedBox(
      width: NextToWatchPosterCard.cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          poster,
          SizedBox(height: gap),
          titleBlock,
          SizedBox(height: gap),
          actionButton,
        ],
      ),
    );
  }

  Widget posterStack(CulturTokens tokens, Color badgeBg, Color badgeFg) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CulturPosterImage(
          imageUrl: widget.item.media.imageUrl,
          width: double.infinity,
          height: double.infinity,
          borderRadius: tokens.borderRadiusTight,
          mediaType: widget.item.media.mediaType,
        ),
        if (widget.item.inPriority)
          NextToWatchCornerBadge(
            alignment: Alignment.topLeft,
            icon: Icons.push_pin,
            label: 'Priority',
            background: badgeBg,
            foreground: badgeFg,
          ),
        if (widget.item.inCinema)
          NextToWatchCornerBadge(
            alignment: Alignment.topRight,
            icon: Icons.theaters,
            label: 'Cinema',
            background: badgeBg,
            foreground: badgeFg,
          ),
      ],
    );
  }
}
