class BookEditFieldInfo {
  const BookEditFieldInfo({
    required this.key,
    required this.label,
    required this.multiline,
    required this.currentValue,
    required this.source,
  });

  factory BookEditFieldInfo.fromJson(Map<String, dynamic> json) {
    return BookEditFieldInfo(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      multiline: json['multiline'] == true,
      currentValue: json['currentValue']?.toString() ?? '',
      source: json['source']?.toString() ?? 'current',
    );
  }

  final String key;
  final String label;
  final bool multiline;
  final String currentValue;
  final String source;
}

class BookEditFieldsResponse {
  const BookEditFieldsResponse({
    required this.mediaId,
    required this.fields,
  });

  factory BookEditFieldsResponse.fromJson(Map<String, dynamic> json) {
    final fields = (json['fields'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(BookEditFieldInfo.fromJson)
        .toList();
    return BookEditFieldsResponse(
      mediaId: json['mediaId']?.toString() ?? '',
      fields: fields,
    );
  }

  final String mediaId;
  final List<BookEditFieldInfo> fields;
}

class BookFieldOption {
  const BookFieldOption({
    required this.provider,
    required this.label,
    required this.displayValue,
    this.value,
    this.metadataPatch,
  });

  factory BookFieldOption.fromJson(Map<String, dynamic> json) {
    return BookFieldOption(
      provider: json['provider']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      displayValue: json['displayValue']?.toString() ?? '',
      value: json['value'],
      metadataPatch: json['metadataPatch'] is Map
          ? Map<String, dynamic>.from(json['metadataPatch'] as Map)
          : null,
    );
  }

  final String provider;
  final String label;
  final String displayValue;
  final Object? value;
  final Map<String, dynamic>? metadataPatch;
}

class BookEditSearchHit {
  const BookEditSearchHit({
    required this.source,
    required this.externalId,
    required this.title,
    this.subtitle,
    this.authors,
    this.isbn,
    this.imageUrl,
  });

  factory BookEditSearchHit.fromJson(Map<String, dynamic> json) {
    return BookEditSearchHit(
      source: json['source']?.toString() ?? '',
      externalId: json['externalId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      authors: json['authors']?.toString(),
      isbn: json['isbn']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
    );
  }

  final String source;
  final String externalId;
  final String title;
  final String? subtitle;
  final String? authors;
  final String? isbn;
  final String? imageUrl;

  String get sourceLabel => switch (source) {
        'porbase' => 'PORBASE',
        'hardcover' => 'Hardcover',
        'openlibrary' => 'Open Library',
        'musicbrainz' => 'MusicBrainz',
        'lastfm' => 'Last.fm',
        _ => source,
      };
}

class BookEditSearchResponse {
  const BookEditSearchResponse({
    required this.query,
    required this.results,
  });

  factory BookEditSearchResponse.fromJson(Map<String, dynamic> json) {
    final results = (json['results'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(BookEditSearchHit.fromJson)
        .toList();
    return BookEditSearchResponse(
      query: json['query']?.toString() ?? '',
      results: results,
    );
  }

  final String query;
  final List<BookEditSearchHit> results;
}

class BookFieldOptionsResponse {
  const BookFieldOptionsResponse({
    required this.field,
    required this.label,
    required this.multiline,
    required this.currentValue,
    required this.options,
  });

  factory BookFieldOptionsResponse.fromJson(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(BookFieldOption.fromJson)
        .toList();
    return BookFieldOptionsResponse(
      field: json['field']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      multiline: json['multiline'] == true,
      currentValue: json['currentValue']?.toString() ?? '',
      options: options,
    );
  }

  final String field;
  final String label;
  final bool multiline;
  final String currentValue;
  final List<BookFieldOption> options;
}
