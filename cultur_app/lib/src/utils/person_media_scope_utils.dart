import 'package:yamtrack/src/models/catalog/catalog_detail_person.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/utils/musicbrainz_person_utils.dart';
import 'package:yamtrack/src/utils/openlibrary_person_utils.dart';

/// TMDB cast/crew ids are numeric strings (movies and TV).
bool isTmdbPersonId(String? personId) {
  final id = personId?.trim() ?? '';
  return id.isNotEmpty && RegExp(r'^\d+$').hasMatch(id);
}

bool showsFavoritePeopleInMediaScope(LibraryMediaScope scope) {
  return switch (scope) {
    LibraryMediaScope.movie ||
    LibraryMediaScope.tv ||
    LibraryMediaScope.book ||
    LibraryMediaScope.music =>
      true,
    LibraryMediaScope.game || LibraryMediaScope.boardgame => false,
  };
}

bool favoritePersonMatchesMediaScope(
  LibraryMediaScope scope,
  CatalogDetailPerson person,
) {
  final id = person.personId?.trim() ?? '';
  if (id.isEmpty) {
    return false;
  }
  return switch (scope) {
    LibraryMediaScope.movie || LibraryMediaScope.tv => isTmdbPersonId(id),
    LibraryMediaScope.book => isBookAuthorPersonId(id),
    LibraryMediaScope.music => isMusicArtistPersonId(id),
    LibraryMediaScope.game || LibraryMediaScope.boardgame => false,
  };
}

List<CatalogDetailPerson> favoritePeopleForMediaScope(
  LibraryMediaScope scope,
  List<CatalogDetailPerson> people,
) {
  if (!showsFavoritePeopleInMediaScope(scope)) {
    return const [];
  }
  return people
      .where((p) => favoritePersonMatchesMediaScope(scope, p))
      .toList();
}
