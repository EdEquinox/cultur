import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:flutter/material.dart';
import 'package:yamtrack/src/utils/book_progress_utils.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/library/library_tracking_filter_model.dart';
import 'package:yamtrack/src/screens/library/widgets/library_multi_select_filter_sheet.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/models/library/watched_tv_episode_library_row.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

// --- Finished date (only [LibraryCollectionKind.finished]) ---

enum WatchedDatePreset {
  none,
  lastMonth,
  lastHalfYear,
  lastYear,
  unknownDate,
}

String watchedDateChipLabel(WatchedDatePreset p) => switch (p) {
      WatchedDatePreset.none => 'Finished date',
      WatchedDatePreset.lastMonth => 'Last month',
      WatchedDatePreset.lastHalfYear => 'Last 6 months',
      WatchedDatePreset.lastYear => 'Last year',
      WatchedDatePreset.unknownDate => 'Unknown date',
    };

DateTime _startOfTodayLocal() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

bool completedAtMatchesWatchedPreset(DateTime? completedAt, WatchedDatePreset preset) {
  if (preset == WatchedDatePreset.none) {
    return true;
  }
  if (preset == WatchedDatePreset.unknownDate) {
    return completedAt == null;
  }
  if (completedAt == null) {
    return false;
  }
  final today = _startOfTodayLocal();
  final local = completedAt.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final daysAgo = today.difference(day).inDays;
  return switch (preset) {
    WatchedDatePreset.none => true,
    WatchedDatePreset.lastMonth => daysAgo >= 0 && daysAgo <= 31,
    WatchedDatePreset.lastHalfYear => daysAgo >= 0 && daysAgo <= 186,
    WatchedDatePreset.lastYear => daysAgo >= 0 && daysAgo <= 366,
    WatchedDatePreset.unknownDate => false,
  };
}

bool watchedEpisodeRowMatchesPreset(WatchedTvEpisodeLibraryRow row, WatchedDatePreset preset) {
  if (preset == WatchedDatePreset.none) {
    return true;
  }
  final at = parseWatchInstant(row.watchedAt);
  return completedAtMatchesWatchedPreset(at, preset);
}

// --- TV: rating / status / type ---

const kTvShowStatusLabels = <String, String>{
  'returning': 'Returning',
  'ended': 'Ended',
  'canceled': 'Canceled',
  'in_production': 'In production',
  'pilot': 'Pilot',
  'planned': 'Planned',
};

const kTvShowTypeLabels = <String, String>{
  'scripted': 'Scripted',
  'documentary': 'Documentary',
  'miniseries': 'Miniseries',
  'reality': 'Reality',
  'talk_show': 'Talk show',
  'news': 'News',
  'video': 'Video',
};

String? metaLower(CatalogItem m, String key) {
  final v = m.metadata[key]?.toString().trim().toLowerCase();
  return v == null || v.isEmpty ? null : v;
}

String? inferShowStatusBucket(CatalogItem media) {
  final raw = metaLower(media, 'status') ??
      metaLower(media, 'tvStatus') ??
      metaLower(media, 'showStatus');
  if (raw == null) {
    return null;
  }
  if (raw.contains('return')) {
    return 'returning';
  }
  if (raw.contains('end')) {
    return 'ended';
  }
  if (raw.contains('cancel')) {
    return 'canceled';
  }
  if (raw.contains('production') || raw.contains('filming')) {
    return 'in_production';
  }
  if (raw.contains('pilot')) {
    return 'pilot';
  }
  if (raw.contains('plan')) {
    return 'planned';
  }
  return null;
}

String? inferShowTypeBucket(CatalogItem media) {
  final raw = metaLower(media, 'seriesType') ??
      metaLower(media, 'showType') ??
      metaLower(media, 'type');
  if (raw != null) {
    if (raw.contains('document')) {
      return 'documentary';
    }
    if (raw.contains('mini')) {
      return 'miniseries';
    }
    if (raw.contains('reality')) {
      return 'reality';
    }
    if (raw.contains('talk')) {
      return 'talk_show';
    }
    if (raw.contains('news')) {
      return 'news';
    }
    if (raw.contains('video')) {
      return 'video';
    }
    if (raw.contains('script')) {
      return 'scripted';
    }
  }
  final genres = metaLower(media, 'genres');
  if (genres != null) {
    if (genres.contains('documentary')) {
      return 'documentary';
    }
    if (genres.contains('reality')) {
      return 'reality';
    }
    if (genres.contains('news')) {
      return 'news';
    }
    if (genres.contains('talk')) {
      return 'talk_show';
    }
  }
  return null;
}

double? catalogTmdbVoteAverage(CatalogItem media) {
  final meta = media.metadata;
  for (final k in ['voteAverage', 'vote_average', 'tmdbRating']) {
    final v = meta[k];
    if (v == null) {
      continue;
    }
    if (v is num) {
      final x = v.toDouble();
      if (x > 0) {
        return x.clamp(0, 10);
      }
      continue;
    }
    final n = double.tryParse(v.toString().trim());
    if (n != null && n > 0) {
      return n.clamp(0, 10);
    }
  }
  return null;
}

bool tvMyRatingMatches(TrackingItem item, bool enabled, int minR, int maxR) {
  if (!enabled) {
    return true;
  }
  final s = item.score;
  if (s == null) {
    return false;
  }
  final r = s.round().clamp(1, 10);
  return r >= minR && r <= maxR;
}

bool tvTmdbRatingMatchesCatalog(CatalogItem media, bool enabled, int minR, int maxR) {
  if (!enabled) {
    return true;
  }
  final v = catalogTmdbVoteAverage(media);
  if (v == null) {
    return false;
  }
  return v >= minR && v <= maxR;
}

bool tvEpisodeMyRatingMatches(
  WatchedTvEpisodeLibraryRow row,
  Map<String, double> scoresByMediaId,
  bool enabled,
  int minR,
  int maxR,
) {
  if (!enabled) {
    return true;
  }
  final s = scoresByMediaId[row.media.id];
  if (s == null) {
    return false;
  }
  final r = s.round().clamp(1, 10);
  return r >= minR && r <= maxR;
}

bool tvShowStatusMatches(CatalogItem media, bool active, Set<String> selectedKeys) {
  if (!active || selectedKeys.isEmpty) {
    return true;
  }
  final bucket = inferShowStatusBucket(media);
  if (bucket == null) {
    return false;
  }
  return selectedKeys.contains(bucket);
}

bool tvShowTypeMatches(CatalogItem media, bool active, Set<String> selectedKeys) {
  if (!active || selectedKeys.isEmpty) {
    return true;
  }
  final bucket = inferShowTypeBucket(media);
  if (bucket == null) {
    return false;
  }
  return selectedKeys.contains(bucket);
}

// --- Collected: metadata (medium etc.) ---

const metadataMediumLabels = <String, String>{
  'digital': 'Digital',
  'ultra_hd_bluray': 'Ultra HD Blu-ray',
  'bluray_3d': 'Blu-ray 3D',
  'bluray': 'Blu-ray',
  'hddvd': 'HD DVD',
  'dvd': 'DVD',
  'vcd': 'Video CD',
  'vhs': 'VHS',
  'betamax': 'Betamax',
  'laserdisc': 'LaserDisc',
};

/// Physical copy vs digital ownership for collected items.
enum CollectedOwnershipKind { physical, digital, unknown }

const _collectedMediumMetadataKeys = <String>[
  'medium',
  'ownedMedium',
  'collectionMedium',
  'format',
  'ownedFormat',
];

bool _metadataBlobContainsMediumKey(CatalogItem media, String mediumKey) {
  final blob = media.metadata.entries
      .map((e) => '${e.key}:${e.value}'.toLowerCase())
      .join(' ');
  final label = metadataMediumLabels[mediumKey]?.toLowerCase() ?? mediumKey;
  return blob.contains(label) || blob.contains(mediumKey.replaceAll('_', ' '));
}

String? _mediumKeyFromRawValue(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  for (final entry in metadataMediumLabels.entries) {
    final keyNorm = entry.key.replaceAll('_', ' ');
    final labelNorm = entry.value.toLowerCase();
    if (normalized == entry.key ||
        normalized == keyNorm ||
        normalized == labelNorm ||
        normalized.contains(keyNorm) ||
        normalized.contains(labelNorm)) {
      return entry.key;
    }
  }
  if (normalized.contains('digital') || normalized.contains('stream')) {
    return 'digital';
  }
  if (normalized.contains('bluray') ||
      normalized.contains('blu-ray') ||
      normalized.contains('dvd') ||
      normalized.contains('vhs') ||
      normalized.contains('disc')) {
    return 'bluray';
  }
  return null;
}

/// Best-effort owned-format key from catalog metadata (AVA / TMDB overlays).
String? inferCollectedMediumKey(CatalogItem media) {
  for (final key in _collectedMediumMetadataKeys) {
    final raw = metaLower(media, key);
    if (raw == null) {
      continue;
    }
    final match = _mediumKeyFromRawValue(raw);
    if (match != null) {
      return match;
    }
  }
  for (final key in metadataMediumLabels.keys) {
    if (_metadataBlobContainsMediumKey(media, key)) {
      return key;
    }
  }
  return null;
}

CollectedOwnershipKind inferCollectedOwnershipKind(CatalogItem media) {
  final key = inferCollectedMediumKey(media);
  if (key == null) {
    return CollectedOwnershipKind.unknown;
  }
  if (key == 'digital') {
    return CollectedOwnershipKind.digital;
  }
  return CollectedOwnershipKind.physical;
}

String collectedOwnershipPillLabel(CollectedOwnershipKind kind) => switch (kind) {
      CollectedOwnershipKind.physical => 'Physical',
      CollectedOwnershipKind.digital => 'Digital',
      CollectedOwnershipKind.unknown => 'Unknown',
    };

String? collectedMediumDetailLabel(CatalogItem media) {
  final key = inferCollectedMediumKey(media);
  if (key == null) {
    return null;
  }
  return metadataMediumLabels[key];
}

bool collectedMetadataMatches(CatalogItem media, bool active, Set<String> selectedKeys) {
  if (!active || selectedKeys.isEmpty) {
    return true;
  }
  final blob = media.metadata.entries
      .map((e) => '${e.key}:${e.value}'.toLowerCase())
      .join(' ');
  for (final key in selectedKeys) {
    final label = metadataMediumLabels[key]?.toLowerCase() ?? key;
    if (blob.contains(label) || blob.contains(key.replaceAll('_', ' '))) {
      return true;
    }
  }
  return false;
}

// --- Universal: genres (all library list surfaces) ---

const genrePickList = <String, String>{
  'action': 'Action',
  'adventure': 'Adventure',
  'animation': 'Animation',
  'comedy': 'Comedy',
  'crime': 'Crime',
  'documentary': 'Documentary',
  'drama': 'Drama',
  'family': 'Family',
  'fantasy': 'Fantasy',
  'history': 'History',
  'horror': 'Horror',
  'kids': 'Kids',
  'music': 'Music',
  'mystery': 'Mystery',
  'reality': 'Reality',
  'romance': 'Romance',
  'science_fiction': 'Science Fiction',
  'soap': 'Soap',
  'thriller': 'Thriller',
  'tv_movie': 'TV Movie',
  'war': 'War',
  'western': 'Western',
};

String genreSlug(String raw) {
  var s = raw.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  s = s.replaceAll(RegExp(r'_+'), '_');
  while (s.startsWith('_')) {
    s = s.substring(1);
  }
  while (s.endsWith('_')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

Set<String> genreSlugsFromCatalog(CatalogItem media) {
  final out = <String>{};
  void consume(dynamic v) {
    if (v == null) {
      return;
    }
    if (v is List) {
      for (final e in v) {
        final slug = genreSlug(e.toString());
        if (slug.isNotEmpty) {
          out.add(slug);
        }
      }
      return;
    }
    final str = v.toString();
    if (str.contains(',')) {
      for (final part in str.split(',')) {
        final slug = genreSlug(part);
        if (slug.isNotEmpty) {
          out.add(slug);
        }
      }
    } else {
      final slug = genreSlug(str);
      if (slug.isNotEmpty) {
        out.add(slug);
      }
    }
  }

  final meta = media.metadata;
  consume(meta['genres']);
  consume(meta['genre']);
  consume(meta['genreNames']);
  return out;
}

bool catalogMatchesGenreSlugs(CatalogItem media, Set<String> selectedSlugs) {
  if (selectedSlugs.isEmpty) {
    return true;
  }
  final have = genreSlugsFromCatalog(media);
  if (have.any(selectedSlugs.contains)) {
    return true;
  }
  final blob = [
    ...have,
    for (final k in ['genres', 'genre', 'genreNames'])
      media.metadata[k]?.toString().toLowerCase() ?? '',
  ].join(' ');
  if (blob.trim().isEmpty) {
    return false;
  }
  for (final slug in selectedSlugs) {
    final label = (genrePickList[slug] ?? slug.replaceAll('_', ' ')).toLowerCase();
    if (label.isNotEmpty && blob.contains(label)) {
      return true;
    }
  }
  return false;
}


// --- Bottom sheets ---

Future<void> showWatchedDatePresetSheet(
  BuildContext context,
  WatchedDatePreset current,
  void Function(WatchedDatePreset value) onApply,
) async {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final tokens = context.culturTokens;
  final chosen = await showModalBottomSheet<WatchedDatePreset>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: scheme.surfaceContainerLow,
    builder: (ctx) {
      Widget optionTile(WatchedDatePreset value, String label) {
        final selected = current == value;
        return Material(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.45)
              : scheme.surfaceContainerHigh,
          borderRadius: tokens.borderRadiusTight,
          clipBehavior: Clip.antiAlias,
          child: RadioListTile<WatchedDatePreset>(
            value: value,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Finished date',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: RadioGroup<WatchedDatePreset>(
                groupValue: current,
                onChanged: (v) {
                  if (v != null) {
                    Navigator.pop(ctx, v);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    optionTile(WatchedDatePreset.none, 'No filter'),
                    const SizedBox(height: 4),
                    optionTile(WatchedDatePreset.lastMonth, 'Last month'),
                    const SizedBox(height: 4),
                    optionTile(WatchedDatePreset.lastHalfYear, 'Last 6 months'),
                    const SizedBox(height: 4),
                    optionTile(WatchedDatePreset.lastYear, 'Last year'),
                    const SizedBox(height: 4),
                    optionTile(WatchedDatePreset.unknownDate, 'Unknown date'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
  if (chosen != null) {
    onApply(chosen);
  }
}

Future<void> showTvRatingFilterSheet(
  BuildContext context,
  LibraryTrackingFilterModel model,
  void Function(LibraryTrackingFilterModel m) onApply,
) async {
  final theme = Theme.of(context);
  var myEnabled = model.tvRatingFilterEnabled;
  var minV = model.tvRatingMin;
  var maxV = model.tvRatingMax;
  var tmdbEnabled = model.tvTmdbRatingFilterEnabled;
  var tmdbMin = model.tvTmdbRatingMin;
  var tmdbMax = model.tvTmdbRatingMax;
  final scheme = theme.colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: scheme.surfaceContainerLow,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModal) {
          void applyNow() {
            model.tvRatingFilterEnabled = myEnabled;
            model.tvRatingMin = minV;
            model.tvRatingMax = maxV;
            model.tvTmdbRatingFilterEnabled = tmdbEnabled;
            model.tvTmdbRatingMin = tmdbMin;
            model.tvTmdbRatingMax = tmdbMax;
            onApply(model);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Rating',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'My rating',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      'Filter by my rating',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                    ),
                    value: myEnabled,
                    onChanged: (v) {
                      setModal(() => myEnabled = v);
                      applyNow();
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(labelText: 'Minimum'),
                          initialValue: minV.clamp(1, 10),
                          items: [
                            for (var i = 1; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i')),
                          ],
                          onChanged: myEnabled
                              ? (v) {
                                  setModal(() {
                                    minV = v ?? 1;
                                    if (minV > maxV) {
                                      maxV = minV;
                                    }
                                  });
                                  applyNow();
                                }
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(labelText: 'Maximum'),
                          initialValue: maxV.clamp(1, 10),
                          items: [
                            for (var i = 1; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i')),
                          ],
                          onChanged: myEnabled
                              ? (v) {
                                  setModal(() {
                                    maxV = v ?? 10;
                                    if (maxV < minV) {
                                      minV = maxV;
                                    }
                                  });
                                  applyNow();
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'TMDb',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      'Filter by TMDb vote average',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                    ),
                    value: tmdbEnabled,
                    onChanged: (v) {
                      setModal(() => tmdbEnabled = v);
                      applyNow();
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(labelText: 'Minimum'),
                          initialValue: tmdbMin.clamp(1, 10),
                          items: [
                            for (var i = 1; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i')),
                          ],
                          onChanged: tmdbEnabled
                              ? (v) {
                                  setModal(() {
                                    tmdbMin = v ?? 1;
                                    if (tmdbMin > tmdbMax) {
                                      tmdbMax = tmdbMin;
                                    }
                                  });
                                  applyNow();
                                }
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(labelText: 'Maximum'),
                          initialValue: tmdbMax.clamp(1, 10),
                          items: [
                            for (var i = 1; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i')),
                          ],
                          onChanged: tmdbEnabled
                              ? (v) {
                                  setModal(() {
                                    tmdbMax = v ?? 10;
                                    if (tmdbMax < tmdbMin) {
                                      tmdbMin = tmdbMax;
                                    }
                                  });
                                  applyNow();
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> showMultiSelectKeySheet(
  BuildContext context, {
  required String title,
  required Map<String, String> keyLabels,
  required Set<String> selected,
  required void Function(Set<String> next) onApply,
}) {
  return showLibraryMultiSelectFilterSheet(
    context,
    title: title,
    keyLabels: keyLabels,
    selected: selected,
    onApply: onApply,
  );
}

String tvRatingFilterChipLabel(LibraryTrackingFilterModel m) {
  final bits = <String>[];
  if (m.tvRatingFilterEnabled) {
    bits.add('${m.tvRatingMin}–${m.tvRatingMax}');
  }
  if (m.tvTmdbRatingFilterEnabled) {
    bits.add('TMDb ${m.tvTmdbRatingMin}–${m.tvTmdbRatingMax}');
  }
  if (bits.isEmpty) {
    return 'Rating';
  }
  return 'Rating (${bits.join(', ')})';
}

DateTime? parseWatchInstant(String? iso) {
  final normalized = iso?.trim() ?? '';
  if (normalized.isEmpty) {
    return null;
  }
  return DateTime.tryParse(
    normalized.endsWith('Z') ? normalized.replaceFirst('Z', '+00:00') : normalized,
  );
}

DateTime calendarDateLocal(DateTime instant) {
  final l = instant.toLocal();
  return DateTime(l.year, l.month, l.day);
}

String? catalogReleaseYear(CatalogItem media) {
  final type = media.mediaType.trim().toLowerCase();
  if (type == 'book') {
    final publishYear = media.metadata['firstPublishYear'];
    if (publishYear != null) {
      final label = publishYear.toString().trim();
      if (label.isNotEmpty) {
        return label;
      }
    }
  }
  if (type == 'boardgame') {
    final published = media.metadata['yearPublished']?.toString().trim();
    if (published != null && published.isNotEmpty) {
      return published;
    }
  }
  final raw = media.metadata['releaseDate']?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  return parsed?.year.toString();
}

int? catalogRuntimeMinutes(CatalogItem media) {
  final meta = media.metadata;
  final keys = ['runtimeMinutes', 'runtime', 'Runtime'];
  for (final k in keys) {
    final v = meta[k];
    if (v is int) {
      return v;
    }
    if (v != null) {
      final n = int.tryParse(v.toString().trim());
      if (n != null) {
        return n;
      }
    }
  }
  return null;
}

Map<String, double> scoresByMediaId(TrackingListData? data) {
  if (data == null) {
    return const {};
  }
  final out = <String, double>{};
  for (final item in data.items) {
    final s = item.score;
    if (s != null) {
      out[item.media.id] = s;
    }
  }
  return out;
}

/// Display label for catalog/tracking row meta (accent line).
String catalogMediaTypeLabel(String mediaType) {
  return switch (mediaType.trim().toLowerCase()) {
    'tv' => 'Series',
    'game' => 'Game',
    'book' => 'Book',
    'boardgame' => 'Board game',
    'music' => 'Album',
    _ => 'Movie',
  };
}

void _appendBookRowMeta(List<String> parts, CatalogItem media) {
  final authors = bookAuthorsLabel(media);
  if (authors != null && !_catalogMetaPartsContain(parts, authors)) {
    parts.add(authors);
  }
  final year = catalogReleaseYear(media);
  if (year != null && !_catalogMetaPartsContain(parts, year)) {
    parts.add(year);
  }
}

List<String> catalogRowMetaPartsForTrackingMedia(
  CatalogItem media, {
  String? mediaTypeOverride,
}) {
  final type = (mediaTypeOverride ?? media.mediaType).trim().toLowerCase();
  final parts = <String>[];
  switch (type) {
    case 'book':
      _appendBookRowMeta(parts, media);
      parts.add('Book');
    case 'tv':
      final year = catalogReleaseYear(media);
      if (year != null) {
        parts.add(year);
      }
      parts.add('Series');
    case 'game':
      final year = catalogReleaseYear(media);
      if (year != null) {
        parts.add(year);
      }
      parts.add('Game');
    case 'boardgame':
      final year = catalogReleaseYear(media);
      if (year != null) {
        parts.add(year);
      }
      parts.add('Board game');
    case 'music':
      final year = catalogReleaseYear(media);
      if (year != null) {
        parts.add(year);
      }
      parts.add('Album');
    default:
      final year = catalogReleaseYear(media);
      if (year != null) {
        parts.add(year);
      }
      final rt = catalogRuntimeMinutes(media);
      if (rt != null) {
        parts.add('$rt min');
      }
      parts.add('Movie');
  }
  if (media.isCatalogPending) {
    parts.insert(0, 'Pending match');
  }
  return parts;
}

/// Compact catalog list meta: type label first (accent), then year · ratings · tags.
List<String> catalogRowMetaPartsForCatalogList(
  CatalogItem item, {
  String? mediaTypeOverride,
}) {
  final type = (mediaTypeOverride ?? item.mediaType).trim().toLowerCase();
  final typeLabel = catalogMediaTypeLabel(type);
  final parts = <String>[typeLabel];

  final sub = item.subtitle?.trim();
  if (sub != null && sub.isNotEmpty) {
    if (sub.contains('·')) {
      for (final segment in sub.split(RegExp(r'\s*·\s*'))) {
        final piece = segment.trim();
        if (piece.isNotEmpty && !_catalogMetaPartDuplicatesLabel(piece, typeLabel)) {
          parts.add(piece);
        }
      }
    } else if (!_catalogMetaPartDuplicatesLabel(sub, typeLabel)) {
      parts.add(sub);
    }
  }

  switch (type) {
    case 'game':
      _appendGameCatalogListMeta(parts, item);
    case 'tv':
      _appendTvCatalogListMeta(parts, item);
    case 'book':
      _appendBookCatalogListMeta(parts, item);
    case 'boardgame':
      _appendBoardgameCatalogListMeta(parts, item);
    case 'music':
      _appendMusicCatalogListMeta(parts, item);
    default:
      _appendMovieCatalogListMeta(parts, item);
  }

  return parts;
}

bool _catalogMetaPartDuplicatesLabel(String piece, String typeLabel) {
  final lower = piece.toLowerCase();
  return lower == typeLabel.toLowerCase() ||
      lower == 'movie' ||
      lower == 'series' ||
      lower == 'game' ||
      lower == 'book' ||
      lower == 'board game' ||
      lower == 'boardgame' ||
      lower == 'album' ||
      lower == 'music';
}

bool _catalogMetaPartsContain(List<String> parts, String value) {
  final needle = value.trim().toLowerCase();
  if (needle.isEmpty) {
    return true;
  }
  for (final part in parts) {
    final hay = part.trim().toLowerCase();
    if (hay == needle || hay.contains(needle) || needle.contains(hay)) {
      return true;
    }
  }
  return false;
}

void _appendGameCatalogListMeta(List<String> parts, CatalogItem item) {
  final year = catalogReleaseYear(item) ??
      item.metadata['firstReleaseDate']?.toString().trim();
  if (year != null && year.isNotEmpty && !_catalogMetaPartsContain(parts, year)) {
    parts.add(year);
  }

  final igdb = item.metadata['igdbRating'];
  if (igdb is num && igdb > 0) {
    final label = 'IGDB ${igdb.toStringAsFixed(1)}';
    if (!_catalogMetaPartsContain(parts, label)) {
      parts.add(label);
    }
  }

  final aggregated = item.metadata['aggregatedRating'];
  if (aggregated is num && aggregated > 0) {
    final label = 'Critics ${aggregated.toStringAsFixed(1)}';
    if (!_catalogMetaPartsContain(parts, label)) {
      parts.add(label);
    }
  }

  final platforms = item.metadata['platforms']?.toString().trim();
  if (platforms != null &&
      platforms.isNotEmpty &&
      !_catalogMetaPartsContain(parts, platforms)) {
    for (final platform in platforms.split(',').map((e) => e.trim())) {
      if (platform.isEmpty) {
        continue;
      }
      if (!_catalogMetaPartsContain(parts, platform)) {
        parts.add(platform);
      }
    }
  }

  final genres = item.metadata['genres']?.toString().trim();
  if (genres != null && genres.isNotEmpty) {
    for (final genre in genres.split(',').map((e) => e.trim())) {
      if (genre.isEmpty || parts.length >= 12) {
        continue;
      }
      if (!_catalogMetaPartsContain(parts, genre)) {
        parts.add(genre);
      }
    }
  }
}

void _appendTvCatalogListMeta(List<String> parts, CatalogItem item) {
  final year = catalogReleaseYear(item);
  if (year != null && !_catalogMetaPartsContain(parts, year)) {
    parts.add(year);
  }
  final vote = catalogTmdbVoteAverage(item);
  if (vote != null) {
    final label = 'TMDB ${vote.toStringAsFixed(1)}';
    if (!_catalogMetaPartsContain(parts, label)) {
      parts.add(label);
    }
  }
}

void _appendBookCatalogListMeta(List<String> parts, CatalogItem item) {
  _appendBookRowMeta(parts, item);
  final pages = bookPageCount(item);
  if (pages != null && pages > 0) {
    final label = pages == 1 ? '1 page' : '$pages pages';
    if (!_catalogMetaPartsContain(parts, label)) {
      parts.add(label);
    }
  }
}

void _appendBoardgameCatalogListMeta(List<String> parts, CatalogItem item) {
  final year = catalogReleaseYear(item);
  if (year != null && !_catalogMetaPartsContain(parts, year)) {
    parts.add(year);
  }
  final rating = item.metadata['bggRating'];
  if (rating is num && rating > 0) {
    final label = 'BGG ${rating.toStringAsFixed(1)}';
    if (!_catalogMetaPartsContain(parts, label)) {
      parts.add(label);
    }
  }
}

void _appendMusicCatalogListMeta(List<String> parts, CatalogItem item) {
  final year = catalogReleaseYear(item);
  if (year != null && !_catalogMetaPartsContain(parts, year)) {
    parts.add(year);
  }
  final rating = item.metadata['communityRating'] ?? item.metadata['discogsRating'];
  if (rating is num && rating > 0) {
    final label = 'Rating ${rating.toStringAsFixed(1)}';
    if (!_catalogMetaPartsContain(parts, label)) {
      parts.add(label);
    }
  }
  final format = item.metadata['format']?.toString().trim();
  if (format != null &&
      format.isNotEmpty &&
      !_catalogMetaPartsContain(parts, format)) {
    parts.add(format);
  }
}

void _appendMovieCatalogListMeta(List<String> parts, CatalogItem item) {
  final year = catalogReleaseYear(item);
  if (year != null && !_catalogMetaPartsContain(parts, year)) {
    parts.add(year);
  }
  final rt = catalogRuntimeMinutes(item);
  if (rt != null) {
    final label = '$rt min';
    if (!_catalogMetaPartsContain(parts, label)) {
      parts.add(label);
    }
  }
  final vote = catalogTmdbVoteAverage(item);
  if (vote != null) {
    final label = 'TMDB ${vote.toStringAsFixed(1)}';
    if (!_catalogMetaPartsContain(parts, label)) {
      parts.add(label);
    }
  }
  final director = item.metadata['director']?.toString().trim() ??
      item.metadata['Director']?.toString().trim();
  if (director != null &&
      director.isNotEmpty &&
      !_catalogMetaPartsContain(parts, director)) {
    parts.add(director);
  }
}

String tvListEntryMixLine(TvCustomList list) {
  var series = 0;
  var seasons = 0;
  var episodes = 0;
  for (final i in list.items) {
    switch (i.entryKind) {
      case TvCustomListEntryKind.show:
        series++;
      case TvCustomListEntryKind.season:
        seasons++;
      case TvCustomListEntryKind.episode:
        episodes++;
    }
  }
  final parts = <String>[];
  if (series > 0) {
    parts.add(series == 1 ? '1 series' : '$series series');
  }
  if (seasons > 0) {
    parts.add(seasons == 1 ? '1 season' : '$seasons seasons');
  }
  if (episodes > 0) {
    parts.add(episodes == 1 ? '1 episode' : '$episodes episodes');
  }
  if (parts.isEmpty) {
    return 'Mixed TV picks';
  }
  return parts.join(' · ');
}

List<String> catalogRowMetaPartsForTvListItem(TvCustomListItem item) {
  final year = catalogReleaseYear(item.show);
  return switch (item.entryKind) {
    TvCustomListEntryKind.show => [
        ?year,
        'Series',
      ],
    TvCustomListEntryKind.season => [
        'Season ${item.seasonNumber}',
        'Series',
      ],
    TvCustomListEntryKind.episode => [
        'S${item.seasonNumber!.toString().padLeft(2, '0')}E${item.episodeNumber!.toString().padLeft(2, '0')}',
        'Episode',
      ],
  };
}

