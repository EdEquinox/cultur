import 'package:yamtrack/src/models/games/game_company_link.dart';
import 'package:yamtrack/src/utils/stored_json_lists.dart';

class FavoriteCompaniesData {
  const FavoriteCompaniesData({required this.companies});

  factory FavoriteCompaniesData.fromJsonString(String? raw) {
    final list = decodeStoredJsonList(raw, GameCompanyLink.fromJson);
    return FavoriteCompaniesData(companies: list);
  }

  final List<GameCompanyLink> companies;

  String toJsonString() =>
      encodeStoredJsonList(companies, (c) => c.toJson());
}
