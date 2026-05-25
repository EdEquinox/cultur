import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/movie/movie_detail_crew_group.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/screens/widgets/movie_crew_chip.dart';

/// Crew department label + horizontal row of compact person cards.
class MediaCrewDepartmentSection extends StatelessWidget {
  const MediaCrewDepartmentSection({
    super.key,
    required this.group,
    required this.onPersonTap,
  });

  final MovieDetailCrewGroup group;
  final ValueChanged<MovieDetailPerson> onPersonTap;

  static const double _rowHeight = MovieCrewChip.minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = group.people;
    if (people.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.title,
          style: CulturCatalogTypography.mutedSectionTitle(theme, theme.colorScheme),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: _rowHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final person = people[index];
              final canOpen = person.personId != null && person.personId!.isNotEmpty;
              return MovieCrewChip(
                person: person,
                onTap: canOpen ? () => onPersonTap(person) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
