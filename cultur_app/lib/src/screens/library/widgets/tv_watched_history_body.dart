import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/library/watched_tv_episode_library_row.dart';
import 'package:yamtrack/src/utils/grouping.dart';
import 'package:yamtrack/src/screens/library/widgets/watched_tv_single_episode_card.dart';
import 'package:yamtrack/src/screens/library/widgets/watched_tv_episode_group_card.dart';

class TvWatchedHistoryBody extends StatefulWidget {
  const TvWatchedHistoryBody({super.key, 
    this.filterHeader,
    required this.rows,
    required this.scoresByMediaId,
    required this.busyKeys,
    required this.onOpenEpisode,
    required this.onRemoveWatched,
    required this.busyKeyFor,
  });

  final Widget? filterHeader;
  final List<WatchedTvEpisodeLibraryRow> rows;
  final Map<String, double> scoresByMediaId;
  final Set<String> busyKeys;
  final void Function(WatchedTvEpisodeLibraryRow row) onOpenEpisode;
  final void Function(WatchedTvEpisodeLibraryRow row) onRemoveWatched;
  final String Function(WatchedTvEpisodeLibraryRow row) busyKeyFor;

  @override
  State<TvWatchedHistoryBody> createState() => TvWatchedHistoryBodyState();
}


class TvWatchedHistoryBodyState extends State<TvWatchedHistoryBody> {
  final Set<String> _expandedGroupKeys = <String>{};

  String _groupKey(DateTime day, String mediaId) =>
      '${day.year}-${day.month}-${day.day}::$mediaId';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final accent = theme.colorScheme.tertiary;
    final byDay = tvEpisodesByCalendarDay(widget.rows);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
      children: [
        if (widget.filterHeader != null) widget.filterHeader!,
        for (final dayEntry in byDay) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              dayEntry.key == kUnknownWatchDay
                  ? 'Unknown date'
                  : loc.formatFullDate(dayEntry.key),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
            for (final block in tvDayEntries(dayEntry.value)) ...[
            if (block is TvDaySingle)
              WatchedTvSingleEpisodeCard(
                row: block.row,
                score: widget.scoresByMediaId[block.row.media.id],
                accentLabelColor: accent,
                isSaving: widget.busyKeys.contains(widget.busyKeyFor(block.row)),
                onOpen: () => widget.onOpenEpisode(block.row),
                onUnwatch: () => widget.onRemoveWatched(block.row),
              )
            else if (block is TvDayGroup)
              WatchedTvEpisodeGroupCard(
                rows: block.rows,
                score: widget.scoresByMediaId[block.rows.first.media.id],
                accentLabelColor: accent,
                expanded: _expandedGroupKeys.contains(_groupKey(dayEntry.key, block.rows.first.media.id)),
                busyKeys: widget.busyKeys,
                busyKeyFor: widget.busyKeyFor,
                onExpansionChanged: (expanded) {
                  setState(() {
                    final key = _groupKey(dayEntry.key, block.rows.first.media.id);
                    if (expanded) {
                      _expandedGroupKeys.add(key);
                    } else {
                      _expandedGroupKeys.remove(key);
                    }
                  });
                },
                onOpenEpisode: widget.onOpenEpisode,
                onRemoveWatched: widget.onRemoveWatched,
              ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}
