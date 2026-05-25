import 'package:yamtrack/src/models/catalog/catalog_item.dart';

DateTime? sortCatalogReleaseDate(CatalogItem media) {
  final raw = media.metadata['releaseDate']?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  if (raw.length >= 10) {
    return DateTime.tryParse(raw.substring(0, 10));
  }
  return DateTime.tryParse(raw);
}

int? sortMetaInt(CatalogItem m, List<String> keys) {
  for (final k in keys) {
    final v = m.metadata[k];
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

DateTime? sortCatalogAirDate(CatalogItem media) {
  for (final k in ['nextEpisodeAirDate', 'lastAirDate', 'last_air_date']) {
    final raw = media.metadata[k]?.toString().trim();
    if (raw != null && raw.isNotEmpty) {
      final d = DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
      if (d != null) {
        return d;
      }
    }
  }
  return null;
}

int compareNullableDate(DateTime? a, DateTime? b, {required bool lastMeansNewest}) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  final c = a.compareTo(b);
  return lastMeansNewest ? -c : c;
}

int compareNullableNum(num? a, num? b, {required bool lastMeansHigh}) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  final c = a.compareTo(b);
  return lastMeansHigh ? -c : c;
}

int compareNullableInt(int? a, int? b, {required bool lastMeansHigh}) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  final c = a.compareTo(b);
  return lastMeansHigh ? -c : c;
}

int compareStrings(String a, String b, {required bool lastMeansDescAlpha}) {
  final c = a.toLowerCase().compareTo(b.toLowerCase());
  return lastMeansDescAlpha ? -c : c;
}
