import 'package:flutter/material.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/movie/movie_catalog_detail.dart';

import 'package:yamtrack/src/models/tv/series_detail.dart';
import 'package:yamtrack/src/providers/tv_catalog_providers.dart';
import 'episode_watched_when_sheet.dart';
import 'rating_stars_row.dart';

class TvMarkWatchedProgressResult {
  const TvMarkWatchedProgressResult({
    required this.throughSeasonNumber,
    required this.throughEpisodeNumber,
    this.score,
    this.watchedAtUtc,
    this.onlySeasonNumber,
  });

  final int throughSeasonNumber;
  final int throughEpisodeNumber;
  final double? score;
  /// Same semantics as [EpisodeWatchedAtSubmit.watchedAtUtc]: `null` = omit in API.
  final DateTime? watchedAtUtc;
  /// When set, mark-through API only touches this season.
  final int? onlySeasonNumber;
}

/// Pick last watched season/episode (aired episodes only).
class TvMarkWatchedProgressSheet extends ConsumerStatefulWidget {
  const TvMarkWatchedProgressSheet({
    super.key,
    required this.mediaId,
    required this.username,
    required this.detail,
    this.lockedSeasonNumber,
  });

  final String mediaId;
  final String username;
  final MovieCatalogDetail detail;
  /// When set, the sheet only adjusts progress within this season (no season picker).
  final int? lockedSeasonNumber;

  @override
  ConsumerState<TvMarkWatchedProgressSheet> createState() => _TvMarkWatchedProgressSheetState();
}

class _TvMarkWatchedProgressSheetState extends ConsumerState<TvMarkWatchedProgressSheet> {
  /// `-1` means “use first season in list” until the user picks explicitly.
  int _seasonNumber = -1;
  int? _episodeNumber;
  int _stars = 0;
  final GlobalKey<EpisodeWatchedWhenBlockState> _whenKey = GlobalKey<EpisodeWatchedWhenBlockState>();

  @override
  void initState() {
    super.initState();
    final locked = widget.lockedSeasonNumber;
    if (locked != null) {
      _seasonNumber = locked;
    }
  }

  List<TvEpisodeCatalog> _airedEpisodes(List<TvEpisodeCatalog> raw) {
    final list = raw.where((e) => tvEpisodeAiredForWatch(e.airDate)).toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return list;
  }

  int _effectiveThroughEpisode(List<TvEpisodeCatalog> aired, int? picked) {
    if (picked != null && aired.any((e) => e.episodeNumber == picked)) {
      return picked;
    }
    return aired.last.episodeNumber;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = widget.detail.media;
    final seasonsAsync = ref.watch(tvSeasonListCatalogProvider(widget.mediaId));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: seasonsAsync.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(apiErrorMessage(e), style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (seasonList) {
            final seasons = seasonList.items.where((s) => s.episodeCount > 0).toList()
              ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
            if (seasons.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No seasons available.', style: theme.textTheme.bodyLarge),
              );
            }

            final effectiveSeason = _seasonNumber >= 0 ? _seasonNumber : seasons.first.seasonNumber;

            final req = TvSeasonDetailCatalogRequest(
              mediaId: widget.mediaId,
              seasonNumber: effectiveSeason,
              username: widget.username.isNotEmpty ? widget.username : null,
            );
            final detailAsync = ref.watch(tvSeasonDetailCatalogProvider(req));
            final seasonDetailData = detailAsync.asData?.value;
            final airedForSave = seasonDetailData != null
                ? _airedEpisodes(seasonDetailData.episodes)
                : <TvEpisodeCatalog>[];
            final canSave = airedForSave.isNotEmpty;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
                      ),
                      Expanded(
                        child: Text(
                          widget.lockedSeasonNumber != null
                              ? 'Episodes in this season'
                              : 'Watched up to',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 28,
                              height: 40,
                              child: media.imageUrl != null && media.imageUrl!.isNotEmpty
                                  ? Image.network(
                                      media.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return ColoredBox(
                                          color: scheme.surfaceContainerHigh,
                                          child: Icon(
                                            Icons.tv_outlined,
                                            size: 18,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        );
                                      },
                                    )
                                  : ColoredBox(
                                      color: scheme.surfaceContainerHigh,
                                      child: Icon(
                                        Icons.tv_outlined,
                                        size: 18,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              media.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (widget.lockedSeasonNumber == null) ...[
                    Text('Season', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: effectiveSeason,
                          items: [
                            for (final s in seasons)
                              DropdownMenuItem(
                                value: s.seasonNumber,
                                child: Text(s.name.isNotEmpty ? s.name : 'Season ${s.seasonNumber}'),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) {
                              return;
                            }
                            setState(() {
                              _seasonNumber = v;
                              _episodeNumber = null;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text('Last episode you watched', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  detailAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Text(apiErrorMessage(e), style: theme.textTheme.bodySmall),
                    data: (seasonDetail) {
                      final aired = _airedEpisodes(seasonDetail.episodes);
                      if (aired.isEmpty) {
                        return Text(
                          'No episodes have aired yet in this season.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                        );
                      }

                      final episodeValue = _effectiveThroughEpisode(aired, _episodeNumber);

                      return InputDecorator(
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            isExpanded: true,
                            value: episodeValue,
                            items: [
                              for (final ep in aired)
                                DropdownMenuItem(
                                  value: ep.episodeNumber,
                                  child: Text('E${ep.episodeNumber} — ${ep.name}'),
                                ),
                            ],
                            onChanged: (v) => setState(() => _episodeNumber = v),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  EpisodeWatchedWhenBlock(key: _whenKey),
                  const SizedBox(height: 20),
                  Text(
                    'Rate this show?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 10),
                  RatingStarsRow(
                    selectedCount: _stars,
                    onChanged: (v) => setState(() => _stars = v),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onPressed: !canSave
                        ? null
                        : () {
                            final sn = effectiveSeason;
                            final en = _effectiveThroughEpisode(airedForSave, _episodeNumber);
                            final score = _stars > 0 ? _stars.toDouble() : null;
                            final when = _whenKey.currentState?.resolveSubmit();
                            Navigator.of(context).pop(
                              TvMarkWatchedProgressResult(
                                throughSeasonNumber: sn,
                                throughEpisodeNumber: en,
                                score: score,
                                watchedAtUtc: when?.watchedAtUtc,
                                onlySeasonNumber: widget.lockedSeasonNumber,
                              ),
                            );
                          },
                    icon: const Icon(Icons.remove_red_eye_outlined),
                    label: const Text('Save'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
