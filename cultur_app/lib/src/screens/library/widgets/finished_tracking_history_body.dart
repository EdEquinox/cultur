import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/library/widgets/finished_tracking_history_row.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

/// Done / Finished library list grouped by [TrackingItem.completedAt] day.
class FinishedTrackingHistoryBody extends StatelessWidget {
  const FinishedTrackingHistoryBody({
    super.key,
    this.filterHeader,
    required this.items,
    required this.savingIds,
    required this.onOpen,
    required this.onRemove,
    required this.removeTooltip,
    required this.removeIcon,
    this.horizontalPadding = librarySearchHorizontalInset,
    this.metaPartsForItem,
    this.undatedSectionTitle = 'Earlier',
  });

  final Widget? filterHeader;
  final List<TrackingItem> items;
  final Set<String> savingIds;
  final ValueChanged<TrackingItem> onOpen;
  final ValueChanged<TrackingItem> onRemove;
  final String removeTooltip;
  final IconData removeIcon;
  final double horizontalPadding;
  final List<String> Function(TrackingItem item)? metaPartsForItem;
  final String undatedSectionTitle;

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
    for (final bucket in dayBuckets.values) {
      bucket.sort(
        (a, b) => (b.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    }
    final sortedDays = dayBuckets.keys.toList()..sort((a, b) => b.compareTo(a));

    final accent = theme.colorScheme.tertiary;

    Widget rowFor(TrackingItem item) {
      return FinishedTrackingHistoryRow(
        item: item,
        isSaving: savingIds.contains(item.id),
        accentLabelColor: accent,
        removeTooltip: removeTooltip,
        removeIcon: removeIcon,
        metaPartsForItem: metaPartsForItem,
        onOpen: () => onOpen(item),
        onRemove: () => onRemove(item),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 8, 16, 132),
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
            rowFor(item),
            const SizedBox(height: 10),
          ],
        ],
        if (undated.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              undatedSectionTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final item in undated) ...[
            rowFor(item),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}
