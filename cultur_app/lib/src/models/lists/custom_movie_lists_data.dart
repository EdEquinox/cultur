import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/utils/stored_json_lists.dart';

class CustomMovieListsData {
  const CustomMovieListsData({required this.lists});

  factory CustomMovieListsData.fromJsonString(String? raw) {
    final lists = decodeStoredJsonList(raw, CustomMovieList.fromJson,
        compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return CustomMovieListsData(lists: lists);
  }

  final List<CustomMovieList> lists;

  String toJsonString() =>
      encodeStoredJsonList(lists, (list) => list.toJson());
}
