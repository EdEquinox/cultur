/// Cast/crew person on a catalog detail screen.
class CatalogDetailPerson {
  const CatalogDetailPerson({
    this.personId,
    required this.name,
    this.role,
    this.imageUrl,
  });

  factory CatalogDetailPerson.fromJson(Map<String, dynamic> json) {
    final rawId = json['personId'];
    final idStr = rawId?.toString().trim() ?? '';
    return CatalogDetailPerson(
      personId: idStr.isEmpty ? null : idStr,
      name: json['name']?.toString() ?? '',
      role: json['role']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
    );
  }

  final String? personId;
  final String name;
  final String? role;
  final String? imageUrl;

  Map<String, dynamic> toFavoriteJson() {
    return {
      if (personId != null && personId!.isNotEmpty) 'personId': personId,
      'name': name,
      if (imageUrl != null && imageUrl!.trim().isNotEmpty) 'imageUrl': imageUrl,
    };
  }
}
