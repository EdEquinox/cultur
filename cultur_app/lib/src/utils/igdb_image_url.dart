/// IGDB CDN helpers — API often returns `t_thumb` (~90px); covers max out at `cover_big_2x`.
const _igdbCdnHost = 'images.igdb.com';
const _igdbCoverSize = 't_cover_big_2x';

String? igdbDisplayImageUrl(String? url, {String? source}) {
  final raw = url?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  if (source != null && source != 'igdb' && !raw.contains(_igdbCdnHost)) {
    return raw;
  }
  if (!raw.contains(_igdbCdnHost)) {
    return raw;
  }

  final normalized = raw.startsWith('http') ? raw : 'https:$raw';
  final match = RegExp(r'/t_[^/]+/([a-z0-9]+)\.(jpg|webp|png)', caseSensitive: false)
      .firstMatch(normalized);
  if (match == null) {
    return normalized;
  }
  final imageId = match.group(1)!;
  final ext = match.group(2)!.toLowerCase();
  return 'https://$_igdbCdnHost/igdb/image/upload/$_igdbCoverSize/$imageId.$ext';
}

String? catalogItemDisplayImageUrl({
  required String? imageUrl,
  required String source,
}) {
  return igdbDisplayImageUrl(imageUrl, source: source);
}
