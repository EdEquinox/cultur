import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';
import 'package:yamtrack/src/screens/widgets/movie_person_card.dart';
import 'package:yamtrack/src/utils/library_item_search.dart';
import 'package:yamtrack/src/utils/person_route_utils.dart';

/// Searchable grid of [MoviePersonCard] for full cast lists.
class CastGridPageBody extends StatefulWidget {
  const CastGridPageBody({
    super.key,
    required this.cast,
    this.emptyTitle = 'No cast listed',
    this.emptyMessage = 'There is no cast information for this title.',
  });

  final List<MovieDetailPerson> cast;
  final String emptyTitle;
  final String emptyMessage;

  @override
  State<CastGridPageBody> createState() => _CastGridPageBodyState();
}

class _CastGridPageBodyState extends State<CastGridPageBody> {
  late final TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openPerson(MovieDetailPerson person) {
    final id = person.personId;
    if (id == null || id.isEmpty) {
      return;
    }
    context.push(personAppRoutePath(id));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cast.isEmpty) {
      return EmptyState(
        title: widget.emptyTitle,
        message: widget.emptyMessage,
        icon: Icons.people_outline,
      );
    }

    final filtered = widget.cast
        .where((person) => castPersonMatchesLibrarySearch(person, _searchQuery))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            librarySearchHorizontalInset,
            12,
            librarySearchHorizontalInset,
            0,
          ),
          child: LibraryItemSearchField(
            controller: _searchController,
            hintText: 'Search cast…',
            registerForPageSearchFab: true,
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyState(
                  title: 'No matches',
                  message: 'Try a different name or character.',
                  icon: Icons.search_off_outlined,
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: MoviePersonCard.cardWidth + 8,
                    mainAxisExtent: MoviePersonCard.gridMainAxisExtent,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final person = filtered[index];
                    final canOpen =
                        person.personId != null && person.personId!.isNotEmpty;
                    return MoviePersonCard(
                      person: person,
                      width: null,
                      onTap: canOpen ? () => _openPerson(person) : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
