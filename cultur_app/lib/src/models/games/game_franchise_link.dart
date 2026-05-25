class GameFranchiseLink {
  const GameFranchiseLink({
    required this.franchiseId,
    required this.name,
    this.slug,
    this.seriesKind,
  });

  factory GameFranchiseLink.fromJson(Map<String, dynamic> json) {
    return GameFranchiseLink(
      franchiseId: json['franchiseId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString(),
      seriesKind: json['seriesKind']?.toString(),
    );
  }

  final String franchiseId;
  final String name;
  final String? slug;
  final String? seriesKind;

  bool get isValid => franchiseId.isNotEmpty && name.trim().isNotEmpty;

  String? get igdbUrl {
    final s = slug?.trim();
    if (s == null || s.isEmpty) {
      return null;
    }
    if (seriesKind == 'collection') {
      return 'https://www.igdb.com/collections/$s';
    }
    return 'https://www.igdb.com/franchises/$s';
  }
}
