import 'package:yamtrack/src/models/catalog/catalog_item.dart';

String? bookSeriesKey(CatalogItem media) {
  final raw = media.metadata['bookSeriesKey'];
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

String? bookSeriesName(CatalogItem media) {
  final raw = media.metadata['bookSeriesName'];
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

String? bookSeriesPosition(CatalogItem media) {
  final raw = media.metadata['bookSeriesPosition'];
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

String? openLibrarySeriesUrl(CatalogItem media) {
  final raw = media.metadata['openLibrarySeriesUrl'];
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}
