class GameCollectionLink {
  const GameCollectionLink({
    required this.collectionId,
    required this.name,
    this.slug,
  });

  factory GameCollectionLink.fromJson(Map<String, dynamic> json) {
    return GameCollectionLink(
      collectionId: json['collectionId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString(),
    );
  }

  final String collectionId;
  final String name;
  final String? slug;

  bool get isValid => collectionId.isNotEmpty && name.trim().isNotEmpty;

  String? get igdbUrl {
    final s = slug?.trim();
    if (s == null || s.isEmpty) {
      return null;
    }
    return 'https://www.igdb.com/collections/$s';
  }
}
