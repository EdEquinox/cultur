import 'package:flutter/material.dart';

/// Horizontal segment along a timeline track row (between node centers).
class UpcomingTimelineTrackRowPainter extends CustomPainter {
  UpcomingTimelineTrackRowPainter({
    required this.stationCount,
    required this.rtl,
    required this.lineColor,
    this.nodeYFactor = 0.82,
    this.strokeWidth = 2.5,
  });

  final int stationCount;
  final bool rtl;
  final Color lineColor;
  final double nodeYFactor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (stationCount < 2) {
      return;
    }

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final y = size.height * nodeYFactor;
    final centers = <Offset>[
      for (var i = 0; i < stationCount; i++)
        Offset(
          UpcomingTimelineLayout.nodeCenterX(
            index: i,
            count: stationCount,
            width: size.width,
            rtl: rtl,
          ),
          y,
        ),
    ];

    for (var i = 1; i < centers.length; i++) {
      canvas.drawLine(centers[i - 1], centers[i], paint);
    }
  }

  @override
  bool shouldRepaint(covariant UpcomingTimelineTrackRowPainter oldDelegate) {
    return oldDelegate.stationCount != stationCount ||
        oldDelegate.rtl != rtl ||
        oldDelegate.lineColor != lineColor;
  }
}

/// Vertical gutter between rows at the exit/entry node X.
class UpcomingTimelineRowConnectorPainter extends CustomPainter {
  UpcomingTimelineRowConnectorPainter({
    required this.x,
    required this.lineColor,
    this.strokeWidth = 2.5,
  });

  final double x;
  final Color lineColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant UpcomingTimelineRowConnectorPainter oldDelegate) {
    return oldDelegate.x != x || oldDelegate.lineColor != lineColor;
  }
}

/// Layout math aligned with [Row] + [Expanded] station columns.
abstract final class UpcomingTimelineLayout {
  static const double cardGap = 8;
  static const int maxPostersPerLine = 3;
  static const double minCardWidth = 72;
  static const double maxCardWidth = 100;

  static int columnsForWidth(double width) {
    if (width >= 560) {
      return 3;
    }
    return 2;
  }

  /// Splits N items into row sizes (max 3); 4 → [2, 2], avoids orphan singles.
  static List<int> balancedChunkSizes(int total, {int maxPerRow = maxPostersPerLine}) {
    if (total <= 0) {
      return [];
    }
    if (total <= maxPerRow) {
      return [total];
    }
    if (total == 4) {
      return [2, 2];
    }

    var rowCount = (total / maxPerRow).ceil();
    while (rowCount >= 2) {
      final base = total ~/ rowCount;
      final extra = total % rowCount;
      final sizes = List<int>.generate(
        rowCount,
        (i) => base + (i < extra ? 1 : 0),
      );
      final valid = sizes.every((s) => s <= maxPerRow && s > 1);
      if (valid) {
        return sizes;
      }
      rowCount -= 1;
    }
    return [total];
  }

  static double nodeCenterX({
    required int index,
    required int count,
    required double width,
    required bool rtl,
  }) {
    if (count <= 0) {
      return width / 2;
    }
    final cell = width / count;
    if (!rtl) {
      return cell * (index + 0.5);
    }
    return width - cell * (index + 0.5);
  }

  static double connectorX({
    required int prevCount,
    required double width,
    required bool prevRowRtl,
  }) {
    return nodeCenterX(
      index: prevCount - 1,
      count: prevCount,
      width: width,
      rtl: prevRowRtl,
    );
  }

  static double cardWidthForCount(int itemCount, double cellWidth) {
    if (itemCount <= 0) {
      return maxCardWidth;
    }
    final gaps = cardGap * (itemCount - 1);
    final raw = (cellWidth - gaps) / itemCount;
    return raw.clamp(minCardWidth, maxCardWidth);
  }
}
