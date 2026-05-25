import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/books/book_publisher_link.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail_person.dart';
import 'package:yamtrack/src/screens/widgets/movie_crew_chip.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

/// Publisher chips on book detail — same chip style as authors.
class BookPublishersSection extends StatelessWidget {
  const BookPublishersSection({required this.publishers, super.key});

  final List<BookPublisherLink> publishers;

  @override
  Widget build(BuildContext context) {
    if (publishers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final publisher in publishers)
          MovieCrewChip(
            person: CatalogDetailPerson(
              name: publisher.name,
              role: 'Publisher',
            ),
            onTap: publisher.isValid
                ? () => context.push(
                      bookPublisherDetailPath(
                        publisherId: publisher.publisherId,
                        name: publisher.name,
                      ),
                    )
                : null,
          ),
      ],
    );
  }
}
