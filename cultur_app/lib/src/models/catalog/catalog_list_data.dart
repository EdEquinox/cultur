import 'package:yamtrack/src/models/catalog/catalog_item.dart';

class CatalogListData {
  const CatalogListData({required this.items});

  factory CatalogListData.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogItem.fromJson)
        .toList();
    return CatalogListData(items: items);
  }

  final List<CatalogItem> items;
}
