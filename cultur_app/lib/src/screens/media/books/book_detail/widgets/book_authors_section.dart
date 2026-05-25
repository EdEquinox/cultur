import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail_person.dart';
import 'package:yamtrack/src/screens/widgets/movie_crew_chip.dart';
import 'package:yamtrack/src/utils/person_route_utils.dart';

/// Author chips — same chip style as game detail company / movie crew rows.
class BookAuthorsSection extends StatelessWidget {
  const BookAuthorsSection({required this.authors, super.key});

  final List<CatalogDetailPerson> authors;

  @override
  Widget build(BuildContext context) {
    if (authors.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final author in authors)
          MovieCrewChip(
            person: author,
            onTap: author.personId != null && author.personId!.isNotEmpty
                ? () => context.push(personAppRoutePath(author.personId!))
                : null,
          ),
      ],
    );
  }
}
