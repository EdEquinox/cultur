import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/movie/movie_catalog_detail.dart';
import 'package:yamtrack/src/models/movie/movie_detail_crew_group.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/utils/person_route_utils.dart';

import 'movie_crew_chip.dart';

bool _isDirectorLikeRole(String? role) {
  if (role == null || role.isEmpty) {
    return false;
  }
  final r = role.toLowerCase();
  if (r.contains('photography') ||
      r.contains('second unit') ||
      r.contains('assistant')) {
    return false;
  }
  return r.contains('director') ||
      r.contains('realizador') ||
      r.contains('réalisateur') ||
      r.contains('regisseur') ||
      r.contains('regista');
}

List<MovieDetailPerson> directorPeopleFromCrew(List<MovieDetailCrewGroup> crew) {
  for (final group in crew) {
    if (group.title != 'Directing') {
      continue;
    }
    final matched = <MovieDetailPerson>[];
    for (final p in group.people) {
      if (_isDirectorLikeRole(p.role)) {
        matched.add(p);
      }
    }
    if (matched.isNotEmpty) {
      return matched;
    }
    if (group.people.isNotEmpty) {
      return [group.people.first];
    }
  }
  return const [];
}

List<MovieDetailPerson> directorPeopleFromMetadata(Map<String, dynamic> metadata) {
  final raw = (metadata['director'] ?? metadata['Director'])?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return const [];
  }
  final parts = raw
      .split(RegExp(r'\s*,\s*'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty);
  return [
    for (final name in parts)
      MovieDetailPerson(personId: null, name: name, role: 'Director', imageUrl: null),
  ];
}

List<MovieDetailPerson> directorPeopleForMovieDetail(MovieCatalogDetail detail) {
  final fromCrew = directorPeopleFromCrew(detail.crew);
  if (fromCrew.isNotEmpty) {
    return fromCrew;
  }
  return directorPeopleFromMetadata(detail.media.metadata);
}

List<MovieDetailPerson> directorPeopleForSeason({
  required List<MovieDetailPerson> seasonDirectors,
  MovieCatalogDetail? showDetail,
}) {
  if (seasonDirectors.isNotEmpty) {
    return seasonDirectors;
  }
  if (showDetail == null) {
    return const [];
  }
  return directorPeopleForMovieDetail(showDetail);
}

List<MovieDetailPerson> directorPeopleForEpisode({
  required List<MovieDetailPerson> episodeDirectors,
  MovieCatalogDetail? showDetail,
}) {
  if (episodeDirectors.isNotEmpty) {
    return episodeDirectors;
  }
  if (showDetail == null) {
    return const [];
  }
  return directorPeopleForMovieDetail(showDetail);
}

/// Same pattern as the People tab crew [Card]: section label + [MovieCrewChip] wrap.
class DetailDirectorPeopleCard extends StatelessWidget {
  const DetailDirectorPeopleCard({
    super.key,
    required this.people,
    this.sectionTitle = 'Director',
  });

  final List<MovieDetailPerson> people;
  final String sectionTitle;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
          child:MovieCrewChip(
                person: people[0],
              onTap: people[0].personId != null && people[0].personId!.isNotEmpty
                  ? () => context.push(personAppRoutePath(people[0].personId!))
                  : null,
            ),
          
        );
  }
}
