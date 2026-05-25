import 'package:yamtrack/src/models/catalog/catalog_detail_person.dart';

class CatalogDetailCrewGroup {
  const CatalogDetailCrewGroup({
    required this.title,
    required this.people,
  });

  factory CatalogDetailCrewGroup.fromJson(Map<String, dynamic> json) {
    final people = (json['people'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogDetailPerson.fromJson)
        .toList();
    return CatalogDetailCrewGroup(
      title: json['title']?.toString() ?? '',
      people: people,
    );
  }

  final String title;
  final List<CatalogDetailPerson> people;
}
