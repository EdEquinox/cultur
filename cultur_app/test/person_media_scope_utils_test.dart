import 'package:flutter_test/flutter_test.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail_person.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/utils/person_media_scope_utils.dart';

void main() {
  group('favoritePersonMatchesMediaScope', () {
    test('movies and TV only accept TMDB numeric ids', () {
      const tmdb = CatalogDetailPerson(personId: '12345', name: 'Actor');
      const author = CatalogDetailPerson(personId: 'ol-OL23919A', name: 'Author');
      const artist = CatalogDetailPerson(
        personId: 'mb-artist-6b0e7b5f-9a1c-4c2d-8e3f-1a2b3c4d5e6f',
        name: 'Artist',
      );

      for (final scope in [LibraryMediaScope.movie, LibraryMediaScope.tv]) {
        expect(favoritePersonMatchesMediaScope(scope, tmdb), isTrue);
        expect(favoritePersonMatchesMediaScope(scope, author), isFalse);
        expect(favoritePersonMatchesMediaScope(scope, artist), isFalse);
      }
    });

    test('books only accept author ids', () {
      const tmdb = CatalogDetailPerson(personId: '99', name: 'Actor');
      const author = CatalogDetailPerson(personId: 'hc-42', name: 'Author');

      expect(
        favoritePersonMatchesMediaScope(LibraryMediaScope.book, author),
        isTrue,
      );
      expect(
        favoritePersonMatchesMediaScope(LibraryMediaScope.book, tmdb),
        isFalse,
      );
    });

    test('games and board games hide people', () {
      const tmdb = CatalogDetailPerson(personId: '1', name: 'Actor');
      expect(showsFavoritePeopleInMediaScope(LibraryMediaScope.game), isFalse);
      expect(
        favoritePersonMatchesMediaScope(LibraryMediaScope.game, tmdb),
        isFalse,
      );
    });
  });
}
