import 'package:yamtrack/src/models/books/book_publisher_link.dart';
import 'package:yamtrack/src/utils/stored_json_lists.dart';

class FavoritePublishersData {
  const FavoritePublishersData({required this.publishers});

  factory FavoritePublishersData.fromJsonString(String? raw) {
    final list = decodeStoredJsonList(raw, BookPublisherLink.fromJson);
    return FavoritePublishersData(publishers: list);
  }

  final List<BookPublisherLink> publishers;

  String toJsonString() =>
      encodeStoredJsonList(publishers, (p) => p.toJson());
}
