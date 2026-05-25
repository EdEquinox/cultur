import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/utils/stored_json_lists.dart';

class FavoritePeopleData {
  const FavoritePeopleData({required this.people});

  factory FavoritePeopleData.fromJsonString(String? raw) {
    final people = decodeStoredJsonList(raw, MovieDetailPerson.fromJson)
        .where((p) => (p.personId ?? '').isNotEmpty)
        .toList();
    return FavoritePeopleData(people: people);
  }

  final List<MovieDetailPerson> people;

  String toJsonString() =>
      encodeStoredJsonList(people, (p) => p.toFavoriteJson());
}
