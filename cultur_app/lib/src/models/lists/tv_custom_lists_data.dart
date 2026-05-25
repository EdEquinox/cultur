import 'package:yamtrack/src/models/lists/tv_custom_list.dart';
import 'package:yamtrack/src/utils/stored_json_lists.dart';

class TvCustomListsData {
  const TvCustomListsData({required this.lists});

  factory TvCustomListsData.fromJsonString(String? raw) {
    final lists = decodeStoredJsonList(raw, TvCustomList.fromJson,
        compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return TvCustomListsData(lists: lists);
  }

  final List<TvCustomList> lists;

  String toJsonString() =>
      encodeStoredJsonList(lists, (list) => list.toJson());
}
