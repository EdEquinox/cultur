import 'dart:convert';

List<T> decodeStoredJsonList<T>(
  String? raw,
  T Function(Map<String, dynamic> json) fromJson, {
  int Function(T a, T b)? compare,
}) {
  if (raw == null || raw.trim().isEmpty) {
    return [];
  }
  final decoded = jsonDecode(raw);
  if (decoded is! List<dynamic>) {
    return [];
  }
  final items = decoded
      .whereType<Map<String, dynamic>>()
      .map(fromJson)
      .toList();
  if (compare != null) {
    items.sort(compare);
  }
  return items;
}

String encodeStoredJsonList<T>(
  List<T> items,
  Map<String, dynamic> Function(T item) toJson,
) =>
    jsonEncode(items.map(toJson).toList());
