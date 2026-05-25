import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';

class MovieHomeShelfData {
  const MovieHomeShelfData({
    required this.nowPlaying,
    required this.upcoming,
  });

  factory MovieHomeShelfData.fromJson(Map<String, dynamic> json) {
    return MovieHomeShelfData(
      nowPlaying: CatalogListData.fromJson(
        (json['nowPlaying'] as Map<String, dynamic>?) ?? const {},
      ),
      upcoming: CatalogListData.fromJson(
        (json['upcoming'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  final CatalogListData nowPlaying;
  final CatalogListData upcoming;
}
