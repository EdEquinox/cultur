import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/screens/home/widgets/upcoming_winding_timeline_painter.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_metrics.dart';

/// One timeline station: a release day (or continuation) with up to 3 posters in a row.
typedef UpcomingTimelineSegment = ({
  DateTime day,
  List<CatalogItem> items,
});

/// Serpentine upcoming timeline: track lane (dates + path) above poster cards.
class UpcomingWindingTimeline extends StatelessWidget {
  const UpcomingWindingTimeline({
    required this.dayGroups,
    required this.onItemTap,
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    this.footer,
  });

  final List<({DateTime day, List<CatalogItem> items})> dayGroups;
  final ValueChanged<CatalogItem> onItemTap;
  final EdgeInsetsGeometry padding;
  final Widget? footer;

  static const double maxCardWidth = UpcomingTimelineLayout.maxCardWidth;
  static const double trackHeight = 52;
  static const double connectorHeight = 32;
  static const double cardsTopGap = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = _expandDayGroupsToSegments(dayGroups);
    final rows = _packSegmentsIntoRows(segments);
    final pathColor = theme.colorScheme.primary.withValues(alpha: 0.75);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0)
              LayoutBuilder(
                builder: (context, constraints) {
                  final prev = rows[r - 1];
                  final x = UpcomingTimelineLayout.connectorX(
                    prevCount: prev.length,
                    width: constraints.maxWidth,
                    prevRowRtl: (r - 1).isOdd,
                  );
                  return SizedBox(
                    height: connectorHeight,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: UpcomingTimelineRowConnectorPainter(
                        x: x,
                        lineColor: pathColor,
                      ),
                    ),
                  );
                },
              ),
            _TimelineRowSection(
              segments: rows[r],
              rtl: r.isOdd,
              pathColor: pathColor,
              onItemTap: onItemTap,
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 24),
            footer!,
          ],
        ],
      ),
    );
  }

  /// Splits each day into line chunks (max 3; 4 → 2+2) for serpentine stations.
  static List<UpcomingTimelineSegment> _expandDayGroupsToSegments(
    List<({DateTime day, List<CatalogItem> items})> groups,
  ) {
    final segments = <UpcomingTimelineSegment>[];
    for (final group in groups) {
      final sizes = UpcomingTimelineLayout.balancedChunkSizes(group.items.length);
      var offset = 0;
      for (final size in sizes) {
        segments.add((
          day: group.day,
          items: group.items.sublist(offset, offset + size),
        ));
        offset += size;
      }
    }
    return segments;
  }

  /// At most [UpcomingTimelineLayout.maxPostersPerLine] posters per timeline row.
  static List<List<UpcomingTimelineSegment>> _packSegmentsIntoRows(
    List<UpcomingTimelineSegment> segments,
  ) {
    final maxPerRow = UpcomingTimelineLayout.maxPostersPerLine;
    final rows = <List<UpcomingTimelineSegment>>[];
    var current = <UpcomingTimelineSegment>[];
    var postersInRow = 0;

    for (final segment in segments) {
      final n = segment.items.length;
      if (current.isNotEmpty && postersInRow + n > maxPerRow) {
        rows.add(current);
        current = [];
        postersInRow = 0;
      }
      current.add(segment);
      postersInRow += n;
    }
    if (current.isNotEmpty) {
      rows.add(current);
    }
    return rows;
  }
}

class _TimelineRowSection extends StatelessWidget {
  const _TimelineRowSection({
    required this.segments,
    required this.rtl,
    required this.pathColor,
    required this.onItemTap,
  });

  final List<UpcomingTimelineSegment> segments;
  final bool rtl;
  final Color pathColor;
  final ValueChanged<CatalogItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowWidth = constraints.maxWidth;
        final count = segments.length;
        final textDirection = rtl ? TextDirection.rtl : TextDirection.ltr;
        final cellWidth = rowWidth / count;

        final cardHeights = segments.map((s) {
          final w = UpcomingTimelineLayout.cardWidthForCount(
            s.items.length,
            cellWidth,
          );
          return CulturCatalogGridMetrics.totalHeightForWidth(w);
        });
        final cardsHeight = cardHeights.fold(0.0, (a, b) => a > b ? a : b);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: UpcomingWindingTimeline.trackHeight,
              width: rowWidth,
              child: CustomPaint(
                painter: UpcomingTimelineTrackRowPainter(
                  stationCount: count,
                  rtl: rtl,
                  lineColor: pathColor,
                ),
                child: Directionality(
                  textDirection: textDirection,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final segment in segments)
                        Expanded(
                          child: _TimelineTrackStation(day: segment.day),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: UpcomingWindingTimeline.cardsTopGap),
            SizedBox(
              height: cardsHeight,
              width: rowWidth,
              child: Directionality(
                textDirection: textDirection,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final segment in segments)
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: cellWidth,
                            child: _TimelineCardsRow(
                              items: segment.items,
                              cellWidth: cellWidth,
                              onItemTap: onItemTap,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TimelineTrackStation extends StatelessWidget {
  const _TimelineTrackStation({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              releaseDayLabel(day),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 10,
                height: 1.15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary,
            border: Border.all(color: scheme.surface, width: 2),
          ),
        ),
        const SizedBox(height: 2),
      ],
    );
  }
}

class _TimelineCardsRow extends StatelessWidget {
  const _TimelineCardsRow({
    required this.items,
    required this.cellWidth,
    required this.onItemTap,
  });

  final List<CatalogItem> items;
  final double cellWidth;
  final ValueChanged<CatalogItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : cellWidth;
        final cardWidth = UpcomingTimelineLayout.cardWidthForCount(
          items.length,
          width,
        );

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: UpcomingTimelineLayout.cardGap),
              SizedBox(
                width: cardWidth,
                child: CulturCatalogGridCard(
                  item: items[i],
                  onTap: () => onItemTap(items[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
