import 'package:yamtrack/src/models/library/watched_tv_episode_library_row.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

int seasonEpisodeCompare(WatchedTvEpisodeLibraryRow a, WatchedTvEpisodeLibraryRow b) {
  if (a.seasonNumber != b.seasonNumber) {
    return a.seasonNumber.compareTo(b.seasonNumber);
  }
  return a.episodeNumber.compareTo(b.episodeNumber);
}

(String, String) tvEpisodeRangeLabel(List<WatchedTvEpisodeLibraryRow> rows) {
  final sorted = [...rows]..sort(seasonEpisodeCompare);
  final first = sorted.first;
  final last = sorted.last;
  final a = 'S${first.seasonNumber.toString().padLeft(2, '0')}E${first.episodeNumber.toString().padLeft(2, '0')}';
  final b = 'S${last.seasonNumber.toString().padLeft(2, '0')}E${last.episodeNumber.toString().padLeft(2, '0')}';
  if (a == b) {
    return (a, a);
  }
  return (a, b);
}

String tvEpisodeCode(WatchedTvEpisodeLibraryRow r) {
  return 'S${r.seasonNumber.toString().padLeft(2, '0')}E${r.episodeNumber.toString().padLeft(2, '0')}';
}

DateTime? maxWatchedAt(List<WatchedTvEpisodeLibraryRow> rows) {
  DateTime? max;
  for (final r in rows) {
    final t = parseWatchInstant(r.watchedAt);
    if (t == null) {
      continue;
    }
    if (max == null || t.isAfter(max)) {
      max = t;
    }
  }
  return max;
}

final kUnknownWatchDay = DateTime(1900, 1, 1);

List<MapEntry<DateTime, List<WatchedTvEpisodeLibraryRow>>> tvEpisodesByCalendarDay(
  List<WatchedTvEpisodeLibraryRow> rows,
) {
  final map = <DateTime, List<WatchedTvEpisodeLibraryRow>>{};
  final undated = <WatchedTvEpisodeLibraryRow>[];
  for (final r in rows) {
    final t = parseWatchInstant(r.watchedAt);
    if (t == null) {
      undated.add(r);
      continue;
    }
    final day = calendarDateLocal(t);
    map.putIfAbsent(day, () => []).add(r);
  }
  for (final e in map.values) {
    e.sort((a, b) {
      final ta = parseWatchInstant(a.watchedAt);
      final tb = parseWatchInstant(b.watchedAt);
      if (ta == null && tb == null) {
        return 0;
      }
      if (ta == null) {
        return 1;
      }
      if (tb == null) {
        return -1;
      }
      return tb.compareTo(ta);
    });
  }
  if (undated.isNotEmpty) {
    map[kUnknownWatchDay] = undated;
  }
  final entries = map.entries.toList()
    ..sort((a, b) {
      if (a.key == kUnknownWatchDay) {
        return 1;
      }
      if (b.key == kUnknownWatchDay) {
        return -1;
      }
      return b.key.compareTo(a.key);
    });
  return entries;
}

List<TvDayEntry> tvDayEntries(List<WatchedTvEpisodeLibraryRow> dayRows) {
  final byShow = <String, List<WatchedTvEpisodeLibraryRow>>{};
  for (final r in dayRows) {
    byShow.putIfAbsent(r.media.id, () => []).add(r);
  }
  final showIds = byShow.keys.toList()
    ..sort((a, b) {
      final ma = maxWatchedAt(byShow[a]!);
      final mb = maxWatchedAt(byShow[b]!);
      if (ma == null && mb == null) {
        return 0;
      }
      if (ma == null) {
        return 1;
      }
      if (mb == null) {
        return -1;
      }
      return mb.compareTo(ma);
    });

  final out = <TvDayEntry>[];
  for (final id in showIds) {
    final list = byShow[id]!;
    list.sort((a, b) {
      final ta = parseWatchInstant(a.watchedAt);
      final tb = parseWatchInstant(b.watchedAt);
      if (ta == null && tb == null) {
        return 0;
      }
      if (ta == null) {
        return 1;
      }
      if (tb == null) {
        return -1;
      }
      return tb.compareTo(ta);
    });
    if (list.length == 1) {
      out.add(TvDaySingle(list.first));
    } else {
      out.add(TvDayGroup(list));
    }
  }
  return out;
}

sealed class TvDayEntry {
  const TvDayEntry();
}

final class TvDaySingle extends TvDayEntry {
  const TvDaySingle(this.row);
  final WatchedTvEpisodeLibraryRow row;
}

final class TvDayGroup extends TvDayEntry {
  const TvDayGroup(this.rows);
  final List<WatchedTvEpisodeLibraryRow> rows;
}
