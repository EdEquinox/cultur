import 'package:yamtrack/src/models/catalog/catalog_item.dart';

class TrackingItem {
  const TrackingItem({
    required this.id,
    required this.username,
    required this.media,
    required this.status,
    this.progress,
    this.score,
    this.notes,
    this.completedAt,
    this.startedAt,
    this.droppedAt,
    this.collectedAt,
    this.createdAt,
    this.updatedAt,
    this.episodeWatchedCount,
    this.tvFullyWatched = false,
    this.tvAiredEpisodeTotal,
  });

  factory TrackingItem.fromJson(Map<String, dynamic> json) {
    final ec = json['episodeWatchedCount'];
    final airedTotal = json['tvAiredEpisodeTotal'];
    return TrackingItem(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      media: CatalogItem.fromJson(
        (json['media'] as Map<String, dynamic>?) ?? const {},
      ),
      status: json['status']?.toString() ?? '',
      progress: switch (json['progress']) {
        int value => value,
        String value => int.tryParse(value),
        _ => null,
      },
      score: switch (json['score']) {
        num value => value.toDouble(),
        String value => double.tryParse(value),
        _ => null,
      },
      notes: json['notes']?.toString(),
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'].toString())
          : null,
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'].toString())
          : null,
      droppedAt: json['droppedAt'] != null
          ? DateTime.tryParse(json['droppedAt'].toString())
          : null,
      collectedAt: json['collectedAt'] != null
          ? DateTime.tryParse(json['collectedAt'].toString())
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
      episodeWatchedCount: ec is int ? ec : int.tryParse(ec?.toString() ?? ''),
      tvFullyWatched: json['tvFullyWatched'] == true,
      tvAiredEpisodeTotal: airedTotal is int
          ? airedTotal
          : int.tryParse(airedTotal?.toString() ?? ''),
    );
  }

  final String id;
  final String username;
  final CatalogItem media;
  final String status;
  final int? progress;
  final double? score;
  final String? notes;
  final DateTime? completedAt;
  final DateTime? startedAt;
  final DateTime? droppedAt;
  final DateTime? collectedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? episodeWatchedCount;
  final bool tvFullyWatched;
  final int? tvAiredEpisodeTotal;
}

/// Subtitle line for TV rows when progress is cached on the tracking row.
List<String> trackingTvProgressMetaParts(TrackingItem item) {
  final parts = <String>[];
  final total = item.tvAiredEpisodeTotal;
  final watched = item.episodeWatchedCount;
  if (total != null && total > 0) {
    if (watched != null) {
      parts.add('$watched / $total episodes');
    }
    if (item.progress != null) {
      parts.add('${item.progress}%');
    }
  } else if (item.progress != null) {
    parts.add('${item.progress}%');
  }
  return parts;
}

class TrackingListData {
  const TrackingListData({required this.items});

  factory TrackingListData.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(TrackingItem.fromJson)
        .toList();
    return TrackingListData(items: items);
  }

  final List<TrackingItem> items;
}

const kTrackingFlagPrefix = '[cult.flags]';
const kTrackingOwnedPrefix = '[cult.owned]';
const kTrackingLentPrefix = '[cult.lent]';
const kTrackingPricePrefix = '[cult.price]';
const kTrackingMbReleasePrefix = '[cult.mb_release]';
const kTrackingDiscogsReleasePrefix = '[cult.discogs_release]';
const _lentFieldSeparator = '\u001f';
const kCollectedTrackingFlag = 'collected';
const kWatchlistTrackingFlag = 'watchlist';
const kWatchedTrackingFlag = 'watched';
const kDoingTrackingFlag = 'doing';
const kBuyTrackingFlag = 'buy';
const kPriorityTrackingFlag = 'priority';
const kDroppedTrackingFlag = 'dropped';

Set<String> trackingFlags(TrackingItem? tracking) {
  final notes = tracking?.notes?.trim();
  if (notes == null || !notes.startsWith(kTrackingFlagPrefix)) {
    return <String>{};
  }
  final firstLine = notes.split('\n').first;
  final payload = firstLine.substring(kTrackingFlagPrefix.length);
  return payload
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
}

bool _isStructuredTrackingLine(String line) {
  final t = line.trim();
  return t.startsWith(kTrackingFlagPrefix) ||
      t.startsWith(kTrackingOwnedPrefix) ||
      t.startsWith(kTrackingLentPrefix) ||
      t.startsWith(kTrackingPricePrefix) ||
      t.startsWith(kTrackingMbReleasePrefix) ||
      t.startsWith(kTrackingDiscogsReleasePrefix);
}

String? trackingOwnedReleaseId(String? notes) {
  final value = notes?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final line in value.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith(kTrackingMbReleasePrefix)) {
      final id = trimmed.substring(kTrackingMbReleasePrefix.length).trim();
      return id.isEmpty ? null : id;
    }
    if (trimmed.startsWith(kTrackingDiscogsReleasePrefix)) {
      final id = trimmed.substring(kTrackingDiscogsReleasePrefix.length).trim();
      return id.isEmpty ? null : id;
    }
  }
  return null;
}

@Deprecated('Use trackingOwnedReleaseId')
String? trackingDiscogsReleaseId(String? notes) => trackingOwnedReleaseId(notes);

/// Active loan on a collected title (stored in tracking notes).
class CollectedLentInfo {
  const CollectedLentInfo({
    required this.borrowerName,
    required this.lentAt,
  });

  final String borrowerName;
  final DateTime lentAt;
}

CollectedLentInfo? trackingCollectedLent(String? notes) {
  final value = notes?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final line in value.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith(kTrackingLentPrefix)) {
      continue;
    }
    final payload = trimmed.substring(kTrackingLentPrefix.length).trim();
    if (payload.isEmpty) {
      return null;
    }
    final sep = payload.indexOf(_lentFieldSeparator);
    if (sep <= 0) {
      continue;
    }
    final name = payload.substring(0, sep).trim();
    final atRaw = payload.substring(sep + 1).trim();
    final at = DateTime.tryParse(atRaw);
    if (name.isEmpty || at == null) {
      return null;
    }
    return CollectedLentInfo(borrowerName: name, lentAt: at);
  }
  return null;
}

bool trackingIsCollectedLent(TrackingItem? tracking) =>
    trackingCollectedLent(tracking?.notes) != null;

String? trackingCollectedPrice(String? notes) {
  final value = notes?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final line in value.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith(kTrackingPricePrefix)) {
      final price = trimmed.substring(kTrackingPricePrefix.length).trim();
      return price.isEmpty ? null : price;
    }
  }
  return null;
}

String _encodeLentLine(CollectedLentInfo lent) =>
    '$kTrackingLentPrefix${lent.borrowerName}$_lentFieldSeparator${lent.lentAt.toUtc().toIso8601String()}';

String? trackingCollectedOwnershipKey(String? notes) {
  final value = notes?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final line in value.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith(kTrackingOwnedPrefix)) {
      final key = trimmed.substring(kTrackingOwnedPrefix.length).trim();
      return key.isEmpty ? null : key;
    }
  }
  return null;
}

String? trackingBody(String? notes) {
  final value = notes?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  if (!value.startsWith(kTrackingFlagPrefix)) {
    return value;
  }
  final bodyLines = value
      .split('\n')
      .skip(1)
      .where((line) => !_isStructuredTrackingLine(line))
      .toList();
  if (bodyLines.isEmpty) {
    return null;
  }
  final body = bodyLines.join('\n').trim();
  return body.isEmpty ? null : body;
}

String? composeTrackingNotes({
  required String? existingNotes,
  required Set<String> flags,
  String? ownedStorageKey,
  String? collectedPrice,
  bool clearCollectedPrice = false,
  String? mbReleaseId,
  bool clearMbReleaseId = false,
  CollectedLentInfo? lent,
  bool clearLent = false,
}) {
  final sortedFlags = flags.toList()..sort();
  final prefix = sortedFlags.isEmpty
      ? null
      : '$kTrackingFlagPrefix${sortedFlags.join(',')}';
  final ownedKey = ownedStorageKey ?? trackingCollectedOwnershipKey(existingNotes);
  final ownedLine =
      ownedKey == null || ownedKey.isEmpty ? null : '$kTrackingOwnedPrefix$ownedKey';
  final priceValue = clearCollectedPrice
      ? null
      : (collectedPrice ?? trackingCollectedPrice(existingNotes));
  final priceLine = priceValue == null || priceValue.isEmpty
      ? null
      : '$kTrackingPricePrefix$priceValue';
  final lentInfo = clearLent ? null : (lent ?? trackingCollectedLent(existingNotes));
  final lentLine = lentInfo == null ? null : _encodeLentLine(lentInfo);
  final releaseValue = clearMbReleaseId
      ? null
      : (mbReleaseId ?? trackingOwnedReleaseId(existingNotes));
  final releaseLine = releaseValue == null || releaseValue.isEmpty
      ? null
      : '$kTrackingMbReleasePrefix$releaseValue';
  final body = trackingBody(existingNotes);
  final lines = <String>[
    ?prefix,
    ?ownedLine,
    ?priceLine,
    ?releaseLine,
    ?lentLine,
    ?body,
  ];
  if (lines.isEmpty) {
    return null;
  }
  return lines.join('\n');
}

bool hasTrackingFlag(TrackingItem? tracking, String flag) {
  return trackingFlags(tracking).contains(flag);
}

bool trackingIsWatched(TrackingItem? tracking) {
  final status = tracking?.status.trim().toLowerCase();
  return hasTrackingFlag(tracking, kWatchedTrackingFlag) || status == 'completed';
}

/// TV may only move to Finished when every aired episode is marked watched.
bool trackingCanMarkTvAsWatched(TrackingItem? tracking) {
  if (tracking == null || tracking.media.mediaType != 'tv') {
    return false;
  }
  return tracking.tvFullyWatched;
}

bool trackingIsInWatchlist(TrackingItem? tracking) {
  final status = tracking?.status.trim().toLowerCase();
  return hasTrackingFlag(tracking, kWatchlistTrackingFlag) || status == 'planning';
}

bool trackingIsDoing(TrackingItem? tracking) {
  return hasTrackingFlag(tracking, kDoingTrackingFlag);
}

/// In-progress play/read on detail screens — excludes finished and dropped states.
bool trackingIsActivelyDoing(TrackingItem? tracking) {
  if (tracking == null) {
    return false;
  }
  if (trackingIsDropped(tracking)) {
    return false;
  }
  if (tracking.media.mediaType != 'tv' && trackingIsWatched(tracking)) {
    return false;
  }
  return trackingIsDoing(tracking);
}

/// Library **Watching** tab: in-progress titles with real watch activity.
///
/// For TV, pass [activeTvMediaIds] from [tvActiveWatchingMediaIdsFromShelves] so fully
/// caught-up series (no continue / upcoming shelf row) are excluded.
bool trackingIsInWatchingCollection(
  TrackingItem? tracking, {
  Set<String>? activeTvMediaIds,
}) {
  if (tracking == null) {
    return false;
  }
  if (trackingIsDropped(tracking)) {
    return false;
  }

  final mediaType = tracking.media.mediaType;
  if (trackingIsWatched(tracking)) {
    final stillWatchingNewEpisodes = mediaType == 'tv' &&
        !tracking.tvFullyWatched &&
        (tracking.episodeWatchedCount ?? 0) > 0;
    if (!stillWatchingNewEpisodes) {
      return false;
    }
  }

  if (mediaType == 'tv') {
    final mediaId = tracking.media.id;
    final episodeCount = tracking.episodeWatchedCount ?? 0;
    final status = tracking.status.trim().toLowerCase();
    final inProgress = status == 'in progress' && !trackingIsInWatchlist(tracking);

    if (activeTvMediaIds != null) {
      if (activeTvMediaIds.contains(mediaId)) {
        return true;
      }
      if (trackingIsDoing(tracking) && episodeCount == 0 && inProgress) {
        return true;
      }
      return false;
    }

    // Home shelves still loading — avoid listing caught-up libraries.
    return inProgress;
  }

  if (trackingIsInWatchlist(tracking)) {
    return false;
  }
  return trackingIsDoing(tracking) ||
      tracking.status.trim().toLowerCase() == 'in progress';
}

bool trackingIsBuy(TrackingItem? tracking) {
  return hasTrackingFlag(tracking, kBuyTrackingFlag);
}

bool trackingIsPriority(TrackingItem? tracking) {
  return hasTrackingFlag(tracking, kPriorityTrackingFlag);
}

bool trackingIsDropped(TrackingItem? tracking) {
  final status = tracking?.status.trim().toLowerCase();
  return hasTrackingFlag(tracking, kDroppedTrackingFlag) || status == 'dropped';
}

String subtitleFor(TrackingItem item) {
  final parts = <String>[item.status];
  if (item.score != null) {
    parts.add('${item.score!.toStringAsFixed(1)}/10');
  }
  if (item.progress != null) {
    parts.add('Progress ${item.progress}');
  }
  return parts.join(' • ');
}
