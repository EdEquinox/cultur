import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

/// Author line for list/shelf cards (`metadata.authors` or subtitle before ` · `).
String? bookAuthorsLabel(CatalogItem media) {
  final raw = media.metadata['authors'];
  if (raw is String && raw.trim().isNotEmpty) {
    return raw.trim();
  }
  final subtitle = media.subtitle?.trim();
  if (subtitle == null || subtitle.isEmpty) {
    return null;
  }
  const sep = ' · ';
  final sepIndex = subtitle.indexOf(sep);
  if (sepIndex > 0) {
    return subtitle.substring(0, sepIndex).trim();
  }
  return subtitle;
}

int? bookPageCount(CatalogItem media) {
  final raw = media.metadata['pageCount'];
  if (raw is int && raw > 0) {
    return raw;
  }
  if (raw is num && raw > 0) {
    return raw.round();
  }
  final parsed = int.tryParse(raw?.toString() ?? '');
  if (parsed != null && parsed > 0) {
    return parsed;
  }
  return null;
}

int bookCurrentPage(TrackingItem? tracking) {
  final value = tracking?.progress;
  if (value == null || value < 0) {
    return 0;
  }
  return value;
}

String bookReadingProgressLabel({
  required TrackingItem tracking,
}) {
  final current = bookCurrentPage(tracking);
  final total = bookPageCount(tracking.media);
  if (total != null && total > 0) {
    final pct = bookReadingPercent(current: current, total: total);
    return 'p. $current / $total · $pct%';
  }
  if (current > 0) {
    return 'p. $current';
  }
  return 'Not started';
}

/// Home shelf summary: `12/450 (3%)`.
String bookReadingProgressSummary({
  required TrackingItem tracking,
}) {
  final current = bookCurrentPage(tracking);
  final total = bookPageCount(tracking.media);
  if (total != null && total > 0) {
    final pct = bookReadingPercent(current: current, total: total);
    return '$current/$total ($pct%)';
  }
  if (current > 0) {
    return '$current pages';
  }
  return 'Not started';
}

int bookReadingPercent({required int current, required int total}) {
  if (total <= 0) {
    return 0;
  }
  return ((current / total) * 100).clamp(0, 100).round();
}

double? bookReadingProgressFraction(TrackingItem tracking) {
  final total = bookPageCount(tracking.media);
  if (total == null || total <= 0) {
    return null;
  }
  return (bookCurrentPage(tracking) / total).clamp(0.0, 1.0);
}
