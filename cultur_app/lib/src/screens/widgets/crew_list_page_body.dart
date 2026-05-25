import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/movie/movie_detail_crew_group.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';
import 'package:yamtrack/src/screens/library/widgets/library_search_filter_header.dart';
import 'package:yamtrack/src/screens/widgets/crew_department_filter_options.dart';
import 'package:yamtrack/src/screens/widgets/movie_person_card.dart';
import 'package:yamtrack/src/utils/library_item_search.dart';
import 'package:yamtrack/src/utils/person_route_utils.dart';

/// Full crew list: search, department filter, grid of [MoviePersonCard].
class CrewListPageBody extends StatefulWidget {
  const CrewListPageBody({
    super.key,
    required this.crew,
    this.emptyTitle = 'No crew listed',
    this.emptyMessage = 'There is no crew information for this title.',
  });

  final List<MovieDetailCrewGroup> crew;
  final String emptyTitle;
  final String emptyMessage;

  @override
  State<CrewListPageBody> createState() => _CrewListPageBodyState();
}

class _CrewListPageBodyState extends State<CrewListPageBody> {
  late final TextEditingController _searchController;
  String _searchQuery = '';
  String? _selectedDepartment;

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

  List<String> get _departments => [
        for (final group in widget.crew)
          if (group.title.trim().isNotEmpty) group.title,
      ];

  List<MovieDetailPerson> _filteredPeople() {
    final query = _searchQuery;
    final department = _selectedDepartment;

    return [
      for (final group in widget.crew)
        if (department == null || group.title == department)
          for (final person in group.people)
            if (castPersonMatchesLibrarySearch(person, query)) person,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.crew.isEmpty) {
      return EmptyState(
        title: widget.emptyTitle,
        message: widget.emptyMessage,
        icon: Icons.badge_outlined,
      );
    }

    final people = _filteredPeople();
    final filterOptions = buildCrewDepartmentFilterOptions(
      departments: _departments,
      selectedDepartment: _selectedDepartment,
      onDepartmentChanged: (value) => setState(() => _selectedDepartment = value),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LibrarySearchFilterHeader(
          padding: const EdgeInsets.fromLTRB(
            librarySearchHorizontalInset,
            12,
            librarySearchHorizontalInset,
            0,
          ),
          searchController: _searchController,
          searchHint: 'Search crew…',
          registerSearchForPageFab: true,
          onSearchChanged: (value) => setState(() => _searchQuery = value),
          filterOptions: filterOptions,
          onClearAll: _selectedDepartment != null
              ? () => setState(() => _selectedDepartment = null)
              : null,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: people.isEmpty
              ? const EmptyState(
                  title: 'No matches',
                  message: 'Try another name or department.',
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
                  itemCount: people.length,
                  itemBuilder: (context, index) {
                    final person = people[index];
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
