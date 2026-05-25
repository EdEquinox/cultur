import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';

/// Mixed entries: any combination of series, seasons, and episodes.
class TvCustomList {
  const TvCustomList({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
  });

  factory TvCustomList.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(TvCustomListItem.fromJson)
        .where((e) => e.isValidListEntry)
        .toList();
    return TvCustomList(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled list',
      items: items,
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }

  final String id;
  final String name;
  final List<TvCustomListItem> items;
  final String createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }

  TvCustomList copyWith({
    String? id,
    String? name,
    List<TvCustomListItem>? items,
    String? createdAt,
  }) {
    return TvCustomList(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
