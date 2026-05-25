import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';
import 'package:yamtrack/src/screens/library/widgets/watched_movie_history_card.dart';

class MovieWatchedHistoryBody extends StatelessWidget {
  const MovieWatchedHistoryBody({super.key, 
    this.filterHeader,
    required this.items,
    required this.savingIds,
    required this.onOpen,
    required this.onUnwatch,
  });

  final Widget? filterHeader;
  final List<TrackingItem> items;
  final Set<String> savingIds;
  final ValueChanged<TrackingItem> onOpen;
  final ValueChanged<TrackingItem> onUnwatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final withDates = <({DateTime day, TrackingItem item})>[];
    final undated = <TrackingItem>[];
    for (final item in items) {
      final at = item.completedAt;
      if (at == null) {
        undated.add(item);
      } else {
        withDates.add((day: calendarDateLocal(at), item: item));
      }
    }
    withDates.sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      if (byDay != 0) {
        return byDay;
      }
      final ca = a.item.completedAt!;
      final cb = b.item.completedAt!;
      return cb.compareTo(ca);
    });

    final dayBuckets = <DateTime, List<TrackingItem>>{};
    for (final e in withDates) {
      dayBuckets.putIfAbsent(e.day, () => []).add(e.item);
    }
    for (final e in dayBuckets.values) {
      e.sort((a, b) => (b.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    }
    final sortedDays = dayBuckets.keys.toList()..sort((a, b) => b.compareTo(a));

    final accent = theme.colorScheme.tertiary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
      children: [
        ?filterHeader,
        for (final day in sortedDays) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              loc.formatFullDate(day),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final item in dayBuckets[day]!) ...[
            WatchedMovieHistoryCard(
              item: item,
              isSaving: savingIds.contains(item.id),
              accentLabelColor: accent,
              onOpen: () => onOpen(item),
              onUnwatch: () => onUnwatch(item),
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (undated.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              'Earlier',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final item in undated) ...[
            WatchedMovieHistoryCard(
              item: item,
              isSaving: savingIds.contains(item.id),
              accentLabelColor: accent,
              onOpen: () => onOpen(item),
              onUnwatch: () => onUnwatch(item),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}



