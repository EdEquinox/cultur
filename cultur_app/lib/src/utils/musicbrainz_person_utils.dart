// Music artists in Cultur use Last.fm-backed person ids (`lfm-artist:`).
// Legacy `mb-artist-` / `mb-artist:` ids from older builds still work.

import 'person_route_utils.dart';

const lfmArtistPersonPrefix = 'lfm-artist:';
const mbArtistPersonPrefix = 'mb-artist-';
const mbArtistPersonPrefixColon = 'mb-artist:';

/// Legacy Discogs numeric artist ids (pre-migration).
const legacyDiscogsArtistPersonPrefix = 'discogs-';

bool isMusicArtistPersonId(String personId) {
  final normalized = personId.trim();
  return normalized.startsWith(lfmArtistPersonPrefix) ||
      normalized.startsWith(mbArtistPersonPrefix) ||
      normalized.startsWith(mbArtistPersonPrefixColon) ||
      normalized.startsWith(legacyDiscogsArtistPersonPrefix);
}

/// @deprecated Use [isMusicArtistPersonId].
bool isMusicBrainzArtistPersonId(String personId) => isMusicArtistPersonId(personId);

/// Storage id for follow API / compact MBID (32 hex) or legacy uuid.
String? parseMusicArtistStorageId(String personId) {
  final normalized = personId.trim();
  if (normalized.startsWith(lfmArtistPersonPrefix)) {
    final key = normalized.substring(lfmArtistPersonPrefix.length).trim();
    if (key.startsWith('n/')) {
      return null;
    }
    return normalizeArtistMbid(key);
  }
  return parseMusicBrainzArtistPersonId(personId);
}

/// Normalized MBID for API calls when the person id embeds a UUID.
String? parseMusicBrainzArtistPersonId(String personId) {
  final normalized = personId.trim();
  if (normalized.startsWith(mbArtistPersonPrefix)) {
    return normalizeArtistMbid(normalized.substring(mbArtistPersonPrefix.length));
  }
  if (normalized.startsWith(mbArtistPersonPrefixColon)) {
    return normalizeArtistMbid(normalized.substring(mbArtistPersonPrefixColon.length));
  }
  if (normalized.startsWith(legacyDiscogsArtistPersonPrefix)) {
    final legacy = normalized.substring(legacyDiscogsArtistPersonPrefix.length).trim();
    return legacy.isEmpty ? null : legacy;
  }
  return null;
}

String compactArtistMbid(String mbid) {
  return mbid.trim().replaceAll('-', '').toLowerCase();
}

String normalizeArtistMbid(String raw) {
  final compact = compactArtistMbid(raw);
  if (compact.length == 32) {
    return '${compact.substring(0, 8)}-'
        '${compact.substring(8, 12)}-'
        '${compact.substring(12, 16)}-'
        '${compact.substring(16, 20)}-'
        '${compact.substring(20, 32)}';
  }
  return raw.trim().toLowerCase();
}

String musicArtistPersonId(String storageOrMbid) {
  final raw = storageOrMbid.trim();
  if (raw.startsWith(lfmArtistPersonPrefix) ||
      raw.startsWith(mbArtistPersonPrefix) ||
      raw.startsWith(mbArtistPersonPrefixColon) ||
      raw.startsWith(legacyDiscogsArtistPersonPrefix)) {
    return raw;
  }
  if (raw.startsWith('n/')) {
    return '$lfmArtistPersonPrefix$raw';
  }
  final normalized = normalizeArtistMbid(raw);
  if (normalized.replaceAll('-', '').length == 32) {
    return '$lfmArtistPersonPrefix$normalized';
  }
  return '$lfmArtistPersonPrefix$raw';
}

/// @deprecated Use [musicArtistPersonId].
String musicBrainzArtistPersonId(String mbid) => musicArtistPersonId(mbid);

String musicArtistPersonPath(String storageOrMbid) {
  return personAppRoutePath(musicArtistPersonId(storageOrMbid));
}

/// @deprecated Use [musicArtistPersonPath].
String musicBrainzArtistPersonPath(String mbid) => musicArtistPersonPath(mbid);

String musicBrainzArtistUrl(String mbid) {
  return 'https://musicbrainz.org/artist/${normalizeArtistMbid(mbid)}';
}

bool artistMbidsMatch(String a, String b) {
  return compactArtistMbid(a) == compactArtistMbid(b);
}
