import 'package:yamtrack/src/utils/musicbrainz_person_utils.dart';
import 'package:yamtrack/src/utils/openlibrary_person_utils.dart';

/// Route/catalog id used in navigation (TMDB, ol-*, music mbid path, company id).
String routePersonIdFromFollow({
  required String entityKind,
  required String? sourceCode,
  required String? externalId,
}) {
  final ext = (externalId ?? '').trim();
  final source = (sourceCode ?? '').trim().toLowerCase();
  return switch (entityKind) {
    'music_artist' => musicArtistPersonId(ext),
    'company' => ext,
    'publisher' => ext,
    'person' when source == 'tmdb' => ext,
    'person' when source == 'hardcover' => hardcoverPersonId(ext),
    'person' when isOpenLibraryPersonId(ext) => ext,
    'person' when isHardcoverPersonId(ext) => ext,
    'person' when ext.startsWith('ol-') => ext,
    'person' when ext.startsWith('hc-') => ext,
    _ => ext,
  };
}

/// Payload fields for `POST /backend/follows`.
({String entityKind, String sourceCode, String externalId}) followPayloadFromRouteId({
  required String routePersonId,
  String? companyRole,
}) {
  final id = routePersonId.trim();
  if (isMusicArtistPersonId(id)) {
    final raw = parseMusicBrainzArtistPersonId(id);
    return (
      entityKind: 'music_artist',
      sourceCode: 'musicbrainz',
      externalId: raw ?? id,
    );
  }
  if (isBookAuthorPersonId(id)) {
    if (isHardcoverPersonId(id)) {
      return (
        entityKind: 'person',
        sourceCode: 'hardcover',
        externalId: id.replaceFirst('hc-', ''),
      );
    }
    return (
      entityKind: 'person',
      sourceCode: 'openlibrary',
      externalId: id,
    );
  }
  if (RegExp(r'^\d+$').hasMatch(id)) {
    return (entityKind: 'person', sourceCode: 'tmdb', externalId: id);
  }
  if (companyRole != null) {
    return (entityKind: 'company', sourceCode: 'igdb', externalId: id);
  }
  return (entityKind: 'publisher', sourceCode: 'manual', externalId: id);
}

bool isUuidLike(String value) {
  final text = value.trim();
  return text.length == 36 && text.contains('-');
}
