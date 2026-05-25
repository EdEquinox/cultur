/// Backend catalog / tracking media shape (`BackendMediaResponse`).
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.source,
    required this.externalId,
    required this.mediaType,
    required this.title,
    this.subtitle,
    this.description,
    this.imageUrl,
    required this.metadata,
  });

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    final metaRaw = json['metadata'];
    final Map<String, dynamic> metadata = switch (metaRaw) {
      final Map<String, dynamic> m => Map<String, dynamic>.from(m),
      final Map m => {
          for (final e in m.entries) e.key.toString(): e.value,
        },
      _ => <String, dynamic>{},
    };

    final mediaTypeRaw = (json['mediaType']?.toString() ?? 'movie').trim();

    return CatalogItem(
      id: json['id']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      externalId: json['externalId']?.toString() ?? '',
      mediaType: mediaTypeRaw.isEmpty ? 'movie' : mediaTypeRaw,
      title: json['title']?.toString() ?? '',
      subtitle: _nullableTrimmedString(json['subtitle']),
      description: _nullableTrimmedString(json['description']),
      imageUrl: _nullableTrimmedString(json['imageUrl']),
      metadata: metadata,
    );
  }

  static String? _nullableTrimmedString(dynamic value) {
    final s = value?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  final String id;
  final String source;
  final String externalId;
  final String mediaType;
  final String title;
  final String? subtitle;
  final String? description;
  final String? imageUrl;
  final Map<String, dynamic> metadata;

  /// Imported from Stash/Bookmory but not linked to IGDB (or other catalog) yet.
  bool get isCatalogPending =>
      metadata['catalogPending'] == true || source.startsWith('import-pending');

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source,
      'externalId': externalId,
      'mediaType': mediaType,
      'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (description != null) 'description': description,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'metadata': metadata,
    };
  }
}
