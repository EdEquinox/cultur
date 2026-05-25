class GameFilterOption {
  const GameFilterOption({required this.id, required this.name});

  factory GameFilterOption.fromJson(Map<String, dynamic> json) {
    return GameFilterOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  final String id;
  final String name;

  bool get isValid => id.isNotEmpty && name.isNotEmpty;
}

class GameCatalogFilters {
  const GameCatalogFilters({
    this.platforms = const [],
    this.genres = const [],
    this.gameModes = const [],
    this.playerPerspectives = const [],
    this.gameTypes = const [],
  });

  factory GameCatalogFilters.fromJson(Map<String, dynamic> json) {
    List<GameFilterOption> parseList(String key) {
      return (json[key] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(GameFilterOption.fromJson)
          .where((o) => o.isValid)
          .toList();
    }

    return GameCatalogFilters(
      platforms: parseList('platforms'),
      genres: parseList('genres'),
      gameModes: parseList('gameModes'),
      playerPerspectives: parseList('playerPerspectives'),
      gameTypes: parseList('gameTypes'),
    );
  }

  final List<GameFilterOption> platforms;
  final List<GameFilterOption> genres;
  final List<GameFilterOption> gameModes;
  final List<GameFilterOption> playerPerspectives;
  final List<GameFilterOption> gameTypes;
}
