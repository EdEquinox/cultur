class StashGameEvent {
  const StashGameEvent({
    required this.slug,
    required this.title,
    required this.startsAt,
    required this.stashUrl,
    this.description,
    this.imageUrl,
  });

  factory StashGameEvent.fromJson(Map<String, dynamic> json) {
    return StashGameEvent(
      slug: json['slug']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      startsAt: DateTime.tryParse(json['startsAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      description: _nullable(json['description']),
      imageUrl: _nullable(json['imageUrl']),
      stashUrl: json['stashUrl']?.toString() ?? '',
    );
  }

  static String? _nullable(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  final String slug;
  final String title;
  final DateTime startsAt;
  final String? description;
  final String? imageUrl;
  final String stashUrl;

  /// Plain-text blurb for cards (strips simple HTML from IGDB).
  String? get displayDescription {
    final raw = description?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final plain = raw.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return plain.isEmpty ? null : plain;
  }
}

class StashGameEventsListData {
  const StashGameEventsListData({
    required this.window,
    required this.items,
  });

  factory StashGameEventsListData.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(StashGameEvent.fromJson)
        .toList();
    return StashGameEventsListData(
      window: json['window']?.toString() ?? 'upcoming',
      items: items,
    );
  }

  final String window;
  final List<StashGameEvent> items;
}
