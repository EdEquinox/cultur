import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/catalog/catalog_link.dart';

class PersonFilmographyEntry {
  const PersonFilmographyEntry({
    required this.media,
    this.role,
    this.mediaType = 'movie',
    this.creditKind = 'cast',
    this.department,
    this.genreIds = const [],
    this.genreNames = const [],
    this.voteAverage,
    this.episodeCount,
  });

  factory PersonFilmographyEntry.fromJson(Map<String, dynamic> json) {
    final genreIds = (json['genreIds'] as List<dynamic>? ?? [])
        .map((e) => int.tryParse(e.toString()) ?? 0)
        .where((e) => e > 0)
        .toList();
    final genreNames = (json['genreNames'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final voteRaw = json['voteAverage'];
    return PersonFilmographyEntry(
      media: CatalogItem.fromJson(
        (json['media'] as Map<String, dynamic>?) ?? const {},
      ),
      role: json['role']?.toString(),
      mediaType: json['mediaType']?.toString() ?? 'movie',
      creditKind: json['creditKind']?.toString() ?? 'cast',
      department: json['department']?.toString(),
      genreIds: genreIds,
      genreNames: genreNames,
      voteAverage: switch (voteRaw) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      },
      episodeCount: switch (json['episodeCount']) {
        int v => v,
        String s => int.tryParse(s),
        _ => null,
      },
    );
  }

  final CatalogItem media;
  final String? role;
  final String mediaType;
  final String creditKind;
  final String? department;
  final List<int> genreIds;
  final List<String> genreNames;
  final double? voteAverage;
  final int? episodeCount;
}

class PersonCatalogDetail {
  const PersonCatalogDetail({
    required this.personId,
    required this.name,
    this.biography,
    this.knownForDepartment,
    this.imageUrl,
    this.gender,
    this.birthday,
    this.placeOfBirth,
    required this.filmography,
    required this.popularFilmography,
    required this.links,
  });

  factory PersonCatalogDetail.fromJson(Map<String, dynamic> json) {
    final filmography = (json['filmography'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PersonFilmographyEntry.fromJson)
        .toList();
    final popularFilmography = (json['popularFilmography'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PersonFilmographyEntry.fromJson)
        .toList();
    final links = (json['links'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogLink.fromJson)
        .toList();
    return PersonCatalogDetail(
      personId: json['personId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      biography: json['biography']?.toString(),
      knownForDepartment: json['knownForDepartment']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      gender: json['gender']?.toString(),
      birthday: json['birthday']?.toString(),
      placeOfBirth: json['placeOfBirth']?.toString(),
      filmography: filmography,
      popularFilmography: popularFilmography,
      links: links,
    );
  }

  final String personId;
  final String name;
  final String? biography;
  final String? knownForDepartment;
  final String? imageUrl;
  final String? gender;
  final String? birthday;
  final String? placeOfBirth;
  final List<PersonFilmographyEntry> filmography;
  final List<PersonFilmographyEntry> popularFilmography;
  final List<CatalogLink> links;
}
