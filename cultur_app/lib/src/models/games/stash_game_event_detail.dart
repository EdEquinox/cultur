import 'package:yamtrack/src/models/games/stash_game_event.dart';

class StashEventGameItem {
  const StashEventGameItem({
    required this.slug,
    required this.title,
    required this.stashUrl,
    this.imageUrl,
    this.releaseLabel,
    this.mediaId,
  });

  factory StashEventGameItem.fromJson(Map<String, dynamic> json) {
    return StashEventGameItem(
      slug: json['slug']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      stashUrl: json['stashUrl']?.toString() ?? '',
      imageUrl: _nullable(json['imageUrl']),
      releaseLabel: _nullable(json['releaseLabel']),
      mediaId: _nullable(json['mediaId']),
    );
  }

  static String? _nullable(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  final String slug;
  final String title;
  final String? imageUrl;
  final String? releaseLabel;
  final String stashUrl;
  final String? mediaId;
}

class StashGameEventDetail {
  const StashGameEventDetail({
    required this.event,
    required this.items,
  });

  factory StashGameEventDetail.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(StashEventGameItem.fromJson)
        .toList();
    return StashGameEventDetail(
      event: StashGameEvent.fromJson(json),
      items: items,
    );
  }

  final StashGameEvent event;
  final List<StashEventGameItem> items;
}
