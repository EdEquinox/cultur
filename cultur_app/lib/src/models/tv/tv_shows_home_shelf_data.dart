import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';

class TvShowsHomeShelfData {
  const TvShowsHomeShelfData({
    required this.nextUp,
    required this.upcomingEpisodes,
  });

  factory TvShowsHomeShelfData.fromJson(Map<String, dynamic> json) {
    return TvShowsHomeShelfData(
      nextUp: CatalogListData.fromJson(
        (json['nextUp'] as Map<String, dynamic>?) ?? const {},
      ),
      upcomingEpisodes: CatalogListData.fromJson(
        (json['upcomingEpisodes'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  final CatalogListData nextUp;
  final CatalogListData upcomingEpisodes;
}
