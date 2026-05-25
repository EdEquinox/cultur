import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/providers/person_providers.dart';
import 'package:yamtrack/src/providers/company_providers.dart';
import 'package:yamtrack/src/providers/publisher_providers.dart';
import 'package:yamtrack/src/models/books/book_publisher_link.dart';
import 'package:yamtrack/src/models/games/game_company_link.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/person_media_scope_utils.dart';
import 'package:yamtrack/src/utils/person_route_utils.dart';
import 'package:yamtrack/src/screens/library/widgets/custom_list_card.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';
import 'package:yamtrack/src/screens/library/widgets/tv_custom_list_card.dart';
import 'package:yamtrack/src/utils/library_item_search.dart';
import 'package:yamtrack/src/utils/library_utils.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';


class PersonalListsPage extends ConsumerStatefulWidget {
  const PersonalListsPage({required this.mediaScope, super.key});

  final LibraryMediaScope mediaScope;

  @override
  ConsumerState<PersonalListsPage> createState() => _PersonalListsPageState();
}

class _PersonalListsPageState extends ConsumerState<PersonalListsPage> {
  late final TextEditingController _searchController;

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

  String get _searchQuery => _searchController.text;

  LibraryMediaScope get mediaScope => widget.mediaScope;

  Future<void> _createList(BuildContext context, WidgetRef ref) async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create custom list'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'List name',
              hintText: 'Favorites, Neo-noir, Weekend watch...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    scheduleTextEditingControllerDispose(controller);
    if (name == null || name.trim().isEmpty) {
      return;
    }

    await ref.read(customListsControllerProvider).createList(username, name);
    ref.invalidate(customMovieListsProvider);
  }

  Future<void> _createTvList(BuildContext context, WidgetRef ref) async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create TV list'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'List name',
              hintText: 'Comfort shows, finales to rewatch…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    scheduleTextEditingControllerDispose(controller);
    if (name == null || name.trim().isEmpty) {
      return;
    }

    await ref.read(customTvListsControllerProvider).createList(username, name.trim());
    ref.invalidate(customTvListsProvider);
  }

  Future<void> _createGameList(BuildContext context, WidgetRef ref) async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create game list'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'List name',
              hintText: 'Backlog, Co-op night, GOTY picks…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    scheduleTextEditingControllerDispose(controller);
    if (name == null || name.trim().isEmpty) {
      return;
    }

    await ref.read(customGameListsControllerProvider).createList(username, name.trim());
    ref.invalidate(customGameListsProvider);
  }

  Future<void> _createBoardgameList(BuildContext context, WidgetRef ref) async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create board game list'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'List name',
              hintText: 'Family night, solo queue, trade list…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    scheduleTextEditingControllerDispose(controller);
    if (name == null || name.trim().isEmpty) {
      return;
    }

    await ref.read(customBoardgameListsControllerProvider).createList(username, name.trim());
    ref.invalidate(customBoardgameListsProvider);
  }

  Future<void> _createMusicList(BuildContext context, WidgetRef ref) async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create album list'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'List name',
              hintText: 'Priority listens, vinyl wishlist, live albums…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    scheduleTextEditingControllerDispose(controller);
    if (name == null || name.trim().isEmpty) {
      return;
    }

    await ref.read(customMusicListsControllerProvider).createList(username, name.trim());
    ref.invalidate(customMusicListsProvider);
  }

  Future<void> _createBookList(BuildContext context, WidgetRef ref) async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create book list'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'List name',
              hintText: 'Summer reading, book club, TBR…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    scheduleTextEditingControllerDispose(controller);
    if (name == null || name.trim().isEmpty) {
      return;
    }

    await ref.read(customBookListsControllerProvider).createList(username, name.trim());
    ref.invalidate(customBookListsProvider);
  }

  Widget _searchField({String? hintText}) {
    return LibraryItemSearchField(
      controller: _searchController,
      hintText: hintText ?? _searchHintText,
      onChanged: (_) => setState(() {}),
    );
  }

  bool get _includesFavoriteCompanies =>
      mediaScope == LibraryMediaScope.game ||
      mediaScope == LibraryMediaScope.boardgame;

  bool get _includesFavoritePublishers => mediaScope == LibraryMediaScope.book;

  bool get _showsFavoritePeople => showsFavoritePeopleInMediaScope(mediaScope);

  String get _favoritesSectionTitle {
    if (mediaScope == LibraryMediaScope.music) {
      return 'Followed artists';
    }
    if (_includesFavoritePublishers) {
      return 'Favorite authors & publishers';
    }
    if (_includesFavoriteCompanies) {
      return 'Favorite companies';
    }
    return 'Favorite people';
  }

  String get _searchHintText {
    if (_includesFavoritePublishers) {
      return 'Search lists, authors or publishers…';
    }
    if (_includesFavoriteCompanies) {
      return 'Search lists or companies…';
    }
    return 'Search lists or people…';
  }

  List<MovieDetailPerson> _scopedFavoritePeople(List<MovieDetailPerson> people) {
    return favoritePeopleForMediaScope(mediaScope, people);
  }

  List<MovieDetailPerson> _filteredFavoritePeople(FavoritePeopleData data) {
    return _filteredFavoritePeopleList(_scopedFavoritePeople(data.people));
  }

  List<MovieDetailPerson> _filteredFavoritePeopleList(List<MovieDetailPerson> people) {
    return _scopedFavoritePeople(people)
        .where((p) => personNameMatchesLibrarySearch(p.name, _searchQuery))
        .toList();
  }

  List<GameCompanyLink> _filteredFavoriteCompanies(FavoriteCompaniesData data) {
    return data.companies
        .where((c) => c.isValid && companyMatchesLibrarySearch(c, _searchQuery))
        .toList();
  }

  List<BookPublisherLink> _filteredFavoritePublishers(FavoritePublishersData data) {
    return data.publishers
        .where((p) => p.isValid && publisherMatchesLibrarySearch(p, _searchQuery))
        .toList();
  }

  bool _hasFavoriteEntries({
    required List<MovieDetailPerson> people,
    required List<GameCompanyLink> companies,
    required List<BookPublisherLink> publishers,
  }) =>
      (_showsFavoritePeople && people.isNotEmpty) ||
      (_includesFavoriteCompanies && companies.isNotEmpty) ||
      (_includesFavoritePublishers && publishers.isNotEmpty);

  List<({String name, String? subtitle, String? imageUrl, IconData icon, VoidCallback? onTap})>
      _favoriteChipEntries({
    required List<MovieDetailPerson> people,
    required List<GameCompanyLink> companies,
    required List<BookPublisherLink> publishers,
  }) {
    final entries =
        <({String name, String? subtitle, String? imageUrl, IconData icon, VoidCallback? onTap})>[];

    for (final person in people) {
      final personId = person.personId?.trim() ?? '';
      entries.add((
        name: person.name,
        subtitle: null,
        imageUrl: person.imageUrl?.trim(),
        icon: Icons.person_outlined,
        onTap: personId.isEmpty ? null : () => context.push(personAppRoutePath(personId)),
      ));
    }

    if (_includesFavoriteCompanies) {
      for (final company in companies) {
        entries.add((
          name: company.name,
          subtitle: formatCompanyRoleLabel(company.role),
          imageUrl: company.imageUrl?.trim(),
          icon: Icons.business_outlined,
          onTap: company.isValid
              ? () => context.push(
                    gameCompanyDetailPath(
                      companyId: company.companyId,
                      role: company.role,
                      name: company.name,
                    ),
                  )
              : null,
        ));
      }
    }

    if (_includesFavoritePublishers) {
      for (final publisher in publishers) {
        entries.add((
          name: publisher.name,
          subtitle: 'Publisher',
          imageUrl: null,
          icon: Icons.auto_stories_outlined,
          onTap: publisher.isValid
              ? () => context.push(
                    bookPublisherDetailPath(
                      publisherId: publisher.publisherId,
                      name: publisher.name,
                    ),
                  )
              : null,
        ));
      }
    }

    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return entries;
  }

  List<Widget> _libraryFavoritesSection({
    required BuildContext context,
    required WidgetRef ref,
    required AsyncValue<FavoritePeopleData> favoriteAsync,
    required List<MovieDetailPerson> filteredPeople,
    AsyncValue<FavoriteCompaniesData>? companiesAsync,
    List<GameCompanyLink> filteredCompanies = const [],
    AsyncValue<FavoritePublishersData>? publishersAsync,
    List<BookPublisherLink> filteredPublishers = const [],
  }) {
    final chips = _favoriteChipEntries(
      people: filteredPeople,
      companies: filteredCompanies,
      publishers: filteredPublishers,
    );
    final peopleError = favoriteAsync.hasError;
    final companiesError =
        _includesFavoriteCompanies && (companiesAsync?.hasError ?? false);
    final publishersError =
        _includesFavoritePublishers && (publishersAsync?.hasError ?? false);

    if (!peopleError && !companiesError && !publishersError && chips.isEmpty) {
      return const [];
    }

    return [
      if (peopleError || companiesError || publishersError)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextButton.icon(
            onPressed: () {
              ref.invalidate(favoritePeopleProvider);
              if (_includesFavoriteCompanies) {
                ref.invalidate(favoriteCompaniesProvider);
              }
              if (_includesFavoritePublishers) {
                ref.invalidate(favoritePublishersProvider);
              }
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Could not load favorites — retry'),
          ),
        ),
      if (chips.isNotEmpty) ...[
        Text(
          _favoritesSectionTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final chip = chips[index];
              final imageUrl = chip.imageUrl;
              return InkWell(
                onTap: chip.onTap,
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 72,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        backgroundImage: imageUrl != null && imageUrl.isNotEmpty
                            ? NetworkImage(imageUrl)
                            : null,
                        child: imageUrl == null || imageUrl.isEmpty
                            ? Icon(chip.icon, size: 28)
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chip.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      if (chip.subtitle != null && chip.subtitle!.isNotEmpty)
                        Text(
                          chip.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontSize: 10,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    if (mediaScope == LibraryMediaScope.tv) {
      final lists = ref.watch(customTvListsProvider);
      return Scaffold(
        extendBody: true,
        appBar: CulturAppBar(
          additionalActions: [
            IconButton(
              tooltip: 'Create list',
              onPressed: () => _createTvList(context, ref),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.refresh(customTvListsProvider.future),
              ref.refresh(favoritePeopleProvider.future),
              if (_includesFavoriteCompanies) ref.refresh(favoriteCompaniesProvider.future),
            ]);
          },
          child: lists.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => ErrorState(
              error: error,
              onRetry: () => ref.invalidate(customTvListsProvider),
            ),
            data: (data) {
              final favoriteAsync = ref.watch(favoritePeopleProvider);
              final companiesAsync = _includesFavoriteCompanies
                  ? ref.watch(favoriteCompaniesProvider)
                  : null;
              final favoriteData = switch (favoriteAsync) {
                AsyncData(:final value) => value,
                _ => const FavoritePeopleData(people: []),
              };
              final companiesData = switch (companiesAsync) {
                AsyncData(:final value) => value,
                _ => const FavoriteCompaniesData(companies: []),
              };
              final session = ref.watch(authControllerProvider).asData?.value.session;
              final loggedIn = (session?.username ?? '').isNotEmpty;
              final filteredLists = data.lists
                  .where((l) => listNameMatchesLibrarySearch(l.name, _searchQuery))
                  .toList();
              final filteredPeople = _filteredFavoritePeople(favoriteData);
              final filteredCompanies = _includesFavoriteCompanies
                  ? _filteredFavoriteCompanies(companiesData)
                  : const <GameCompanyLink>[];
              final noTvLists = filteredLists.isEmpty;
              final hasSearch = _searchQuery.trim().isNotEmpty;

              if (!hasSearch &&
                  data.lists.isEmpty &&
                  !_hasFavoriteEntries(
                    people: _scopedFavoritePeople(favoriteData.people),
                    companies: companiesData.companies,
                    publishers: const [],
                  )) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 132),
                  children: [
                    EmptyState(
                      title: loggedIn ? 'Nothing here yet' : 'Nothing here',
                      message: loggedIn
                          ? 'Create custom lists and mix whole series, seasons, and episodes in the same list. '
                              'You can also favorite cast from series and episode pages.'
                          : 'Sign in to view your TV lists and favorite people.',
                      icon: Icons.list_alt_outlined,
                    ),
                    if (loggedIn) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _createTvList(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Create TV list'),
                      ),
                    ],
                  ],
                );
              }

              if (hasSearch &&
                  filteredLists.isEmpty &&
                  !_hasFavoriteEntries(
                    people: filteredPeople,
                    companies: filteredCompanies,
                    publishers: const [],
                  )) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 16, librarySearchHorizontalInset, 132),
                  children: [
                    _searchField(),
                    const SizedBox(height: 24),
                    const EmptyState(
                      title: 'No matches',
                      message: 'Nothing matches your search.',
                      icon: Icons.search_off_outlined,
                    ),
                  ],
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 16, librarySearchHorizontalInset, 132),
                children: [
                  _searchField(),
                  const SizedBox(height: 12),
                  ..._libraryFavoritesSection(
                    context: context,
                    ref: ref,
                    favoriteAsync: favoriteAsync,
                    filteredPeople: filteredPeople,
                    companiesAsync: companiesAsync,
                    filteredCompanies: filteredCompanies,
                    filteredPublishers: const [],
                  ),
                  Text(
                    'Custom TV lists',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Later, Doing, Finished, Owned, and Left tabs live in the bottom bar. '
                    'Each list below can mix series, seasons, and episodes — use Lists on a detail page to add entries.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (noTvLists && loggedIn) ...[
                    FilledButton.icon(
                      onPressed: () => _createTvList(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Create TV list'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  for (var i = 0; i < filteredLists.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    TvCustomListCard(
                      list: filteredLists[i],
                      onTap: () => context.push(
                        '${mediaScope.libraryBasePath}/lists/${filteredLists[i].id}',
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: FloatingLibraryNav(
          currentDestination: FloatingLibraryDestination.personalLists,
          mediaScope: mediaScope,
        ),
      );
    }

    if (mediaScope == LibraryMediaScope.music) {
      final lists = ref.watch(customMusicListsProvider);
      return Scaffold(
        extendBody: true,
        appBar: CulturAppBar(
          additionalActions: [
            IconButton(
              tooltip: 'Create list',
              onPressed: () => _createMusicList(context, ref),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.refresh(customMusicListsProvider.future),
              ref.refresh(favoritePeopleProvider.future),
            ]);
          },
          child: lists.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => ErrorState(
              error: error,
              onRetry: () => ref.invalidate(customMusicListsProvider),
            ),
            data: (data) {
              final session = ref.watch(authControllerProvider).asData?.value.session;
              final loggedIn = (session?.username ?? '').isNotEmpty;
              final favoriteAsync = ref.watch(favoritePeopleProvider);
              final favoriteData = switch (favoriteAsync) {
                AsyncData(:final value) => value,
                _ => const FavoritePeopleData(people: []),
              };
              final filteredPeople = _filteredFavoritePeopleList(favoriteData.people);
              final filteredLists = data.lists
                  .where((l) => listNameMatchesLibrarySearch(l.name, _searchQuery))
                  .toList();
              final hasSearch = _searchQuery.trim().isNotEmpty;
              final customListsOnly = data.lists
                  .where((l) => !BuiltInMusicLists.isBuiltIn(l.id))
                  .toList();
              const listsTitle = 'Album lists';
              const listsBlurb =
                  'Priority queue and custom lists. Pin an album on its detail page, or use Lists to add to a custom list. '
                  'You can also follow artists from album and artist pages.';

              void createList() => _createMusicList(context, ref);

              if (!hasSearch &&
                  customListsOnly.isEmpty &&
                  !_hasFavoriteEntries(
                    people: favoriteData.people,
                    companies: const [],
                    publishers: const [],
                  )) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    librarySearchHorizontalInset,
                    16,
                    librarySearchHorizontalInset,
                    132,
                  ),
                  children: [
                    _searchField(),
                    const SizedBox(height: 12),
                    Text(
                      listsTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      listsBlurb,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    for (final list in data.lists) ...[
                      CustomListCard(
                        list: list,
                        onTap: () => context.push(
                          '${mediaScope.libraryBasePath}/lists/${list.id}',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (loggedIn) ...[
                      FilledButton.icon(
                        onPressed: createList,
                        icon: const Icon(Icons.add),
                        label: const Text('Create custom list'),
                      ),
                    ],
                  ],
                );
              }

              if (hasSearch &&
                  filteredLists.isEmpty &&
                  filteredPeople.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    librarySearchHorizontalInset,
                    16,
                    librarySearchHorizontalInset,
                    132,
                  ),
                  children: [
                    _searchField(),
                    const SizedBox(height: 24),
                    const EmptyState(
                      title: 'No matches',
                      message: 'Nothing matches your search.',
                      icon: Icons.search_off_outlined,
                    ),
                  ],
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  librarySearchHorizontalInset,
                  16,
                  librarySearchHorizontalInset,
                  132,
                ),
                children: [
                  _searchField(),
                  const SizedBox(height: 12),
                  ..._libraryFavoritesSection(
                    context: context,
                    ref: ref,
                    favoriteAsync: favoriteAsync,
                    filteredPeople: filteredPeople,
                    companiesAsync: null,
                    filteredCompanies: const [],
                    publishersAsync: null,
                    filteredPublishers: const [],
                  ),
                  Text(
                    listsTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    listsBlurb,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (customListsOnly.isEmpty && loggedIn) ...[
                    FilledButton.icon(
                      onPressed: createList,
                      icon: const Icon(Icons.add),
                      label: const Text('Create custom list'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  for (var i = 0; i < filteredLists.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    CustomListCard(
                      list: filteredLists[i],
                      onTap: () => context.push(
                        '${mediaScope.libraryBasePath}/lists/${filteredLists[i].id}',
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: FloatingLibraryNav(
          currentDestination: FloatingLibraryDestination.personalLists,
          mediaScope: mediaScope,
        ),
      );
    }

    if (mediaScope == LibraryMediaScope.game ||
        mediaScope == LibraryMediaScope.boardgame ||
        mediaScope == LibraryMediaScope.book) {
      final isBoardgame = mediaScope == LibraryMediaScope.boardgame;
      final isBook = mediaScope == LibraryMediaScope.book;
      final lists = ref.watch(
        isBook
            ? customBookListsProvider
            : isBoardgame
                ? customBoardgameListsProvider
                : customGameListsProvider,
      );
      return Scaffold(
        extendBody: true,
        appBar: CulturAppBar(
          additionalActions: [
            IconButton(
              tooltip: 'Create list',
              onPressed: () {
                if (isBook) {
                  _createBookList(context, ref);
                } else if (isBoardgame) {
                  _createBoardgameList(context, ref);
                } else {
                  _createGameList(context, ref);
                }
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.refresh(
                (isBook
                        ? customBookListsProvider
                        : isBoardgame
                            ? customBoardgameListsProvider
                            : customGameListsProvider)
                    .future,
              ),
              ref.refresh(favoritePeopleProvider.future),
              if (!isBook) ref.refresh(favoriteCompaniesProvider.future),
              if (isBook) ref.refresh(favoritePublishersProvider.future),
            ]);
          },
          child: lists.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => ErrorState(
              error: error,
              onRetry: () => ref.invalidate(
                isBook
                    ? customBookListsProvider
                    : isBoardgame
                        ? customBoardgameListsProvider
                        : customGameListsProvider,
              ),
            ),
            data: (data) {
              final favoriteAsync = ref.watch(favoritePeopleProvider);
              final companiesAsync =
                  isBook ? null : ref.watch(favoriteCompaniesProvider);
              final publishersAsync =
                  isBook ? ref.watch(favoritePublishersProvider) : null;
              final favoriteData = switch (favoriteAsync) {
                AsyncData(:final value) => value,
                _ => const FavoritePeopleData(people: []),
              };
              final companiesData = switch (companiesAsync) {
                AsyncData(:final value) => value,
                _ => const FavoriteCompaniesData(companies: []),
              };
              final publishersData = switch (publishersAsync) {
                AsyncData(:final value) => value,
                _ => const FavoritePublishersData(publishers: []),
              };
              final filteredPeople = _filteredFavoritePeople(favoriteData);
              final filteredCompanies = isBook
                  ? const <GameCompanyLink>[]
                  : _filteredFavoriteCompanies(companiesData);
              final filteredPublishers = isBook
                  ? _filteredFavoritePublishers(publishersData)
                  : const <BookPublisherLink>[];
              final session = ref.watch(authControllerProvider).asData?.value.session;
              final loggedIn = (session?.username ?? '').isNotEmpty;
              final filteredLists = data.lists
                  .where((l) => listNameMatchesLibrarySearch(l.name, _searchQuery))
                  .toList();
              final hasSearch = _searchQuery.trim().isNotEmpty;

              final customListsOnly = data.lists
                  .where(
                    (l) => isBook
                        ? !BuiltInBookLists.isBuiltIn(l.id)
                        : isBoardgame
                            ? !BuiltInBoardgameLists.isBuiltIn(l.id)
                            : !BuiltInGameLists.isBuiltIn(l.id),
                  )
                  .toList();

              final listsTitle = isBook
                  ? 'Book lists'
                  : isBoardgame
                      ? 'Board game lists'
                      : 'Game lists';
              final listsBlurb = isBook
                  ? 'Priority queue and custom lists. Pin a book on its detail page, or use Lists to add to a custom list. '
                      'You can also favorite authors and publishers from book pages.'
                  : isBoardgame
                      ? 'Priority queue and custom lists. Pin a board game on its detail page, or use Lists to add to a custom list. '
                          'You can also favorite companies from game pages.'
                      : 'Priority queue, pending imports (after Stash import), and custom lists. '
                          'Pin a game for priority, or open a pending title to link it in IGDB. '
                          'You can also favorite companies from game pages.';

              void createList() {
                if (isBook) {
                  _createBookList(context, ref);
                } else if (isBoardgame) {
                  _createBoardgameList(context, ref);
                } else {
                  _createGameList(context, ref);
                }
              }

              if (!hasSearch &&
                  customListsOnly.isEmpty &&
                  !_hasFavoriteEntries(
                    people: _scopedFavoritePeople(favoriteData.people),
                    companies: companiesData.companies,
                    publishers: publishersData.publishers,
                  )) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    librarySearchHorizontalInset,
                    16,
                    librarySearchHorizontalInset,
                    132,
                  ),
                  children: [
                    _searchField(),
                    const SizedBox(height: 12),
                    Text(
                      listsTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      listsBlurb,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    for (final list in data.lists) ...[
                      CustomListCard(
                        list: list,
                        onTap: () => context.push(
                          '${mediaScope.libraryBasePath}/lists/${list.id}',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (loggedIn) ...[
                      FilledButton.icon(
                        onPressed: createList,
                        icon: const Icon(Icons.add),
                        label: const Text('Create custom list'),
                      ),
                    ],
                  ],
                );
              }

              if (hasSearch &&
                  filteredLists.isEmpty &&
                  !_hasFavoriteEntries(
                    people: filteredPeople,
                    companies: filteredCompanies,
                    publishers: filteredPublishers,
                  )) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    librarySearchHorizontalInset,
                    16,
                    librarySearchHorizontalInset,
                    132,
                  ),
                  children: [
                    _searchField(),
                    const SizedBox(height: 24),
                    const EmptyState(
                      title: 'No matches',
                      message: 'Nothing matches your search.',
                      icon: Icons.search_off_outlined,
                    ),
                  ],
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  librarySearchHorizontalInset,
                  16,
                  librarySearchHorizontalInset,
                  132,
                ),
                children: [
                  _searchField(),
                  const SizedBox(height: 12),
                  ..._libraryFavoritesSection(
                    context: context,
                    ref: ref,
                    favoriteAsync: favoriteAsync,
                    filteredPeople: filteredPeople,
                    companiesAsync: companiesAsync,
                    filteredCompanies: filteredCompanies,
                    publishersAsync: publishersAsync,
                    filteredPublishers: filteredPublishers,
                  ),
                  Text(
                    listsTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    listsBlurb,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (customListsOnly.isEmpty && loggedIn) ...[
                    FilledButton.icon(
                      onPressed: createList,
                      icon: const Icon(Icons.add),
                      label: const Text('Create custom list'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  for (var i = 0; i < filteredLists.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    CustomListCard(
                      list: filteredLists[i],
                      onTap: () => context.push(
                        '${mediaScope.libraryBasePath}/lists/${filteredLists[i].id}',
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: FloatingLibraryNav(
          currentDestination: FloatingLibraryDestination.personalLists,
          mediaScope: mediaScope,
        ),
      );
    }

    final lists = ref.watch(customMovieListsProvider);

    return Scaffold(
      extendBody: true,
      appBar: CulturAppBar(
        additionalActions: [
          IconButton(
            tooltip: 'Create list',
            onPressed: () => _createList(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.refresh(customMovieListsProvider.future),
            ref.refresh(favoritePeopleProvider.future),
            if (_includesFavoriteCompanies) ref.refresh(favoriteCompaniesProvider.future),
          ]);
        },
        child: lists.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(customMovieListsProvider),
          ),
          data: (data) {
            final favoriteAsync = ref.watch(favoritePeopleProvider);
            final companiesAsync = _includesFavoriteCompanies
                ? ref.watch(favoriteCompaniesProvider)
                : null;
            final favoriteData = switch (favoriteAsync) {
              AsyncData(:final value) => value,
              _ => const FavoritePeopleData(people: []),
            };
            final companiesData = switch (companiesAsync) {
              AsyncData(:final value) => value,
              _ => const FavoriteCompaniesData(companies: []),
            };
            final session = ref.watch(authControllerProvider).asData?.value.session;
            final loggedIn = (session?.username ?? '').isNotEmpty;

            final filteredLists = data.lists
                .where((l) => listNameMatchesLibrarySearch(l.name, _searchQuery))
                .toList();
            final filteredPeople = _filteredFavoritePeople(favoriteData);
            final filteredCompanies = _includesFavoriteCompanies
                ? _filteredFavoriteCompanies(companiesData)
                : const <GameCompanyLink>[];
            final hasSearch = _searchQuery.trim().isNotEmpty;

            if (!hasSearch &&
                data.lists.isEmpty &&
                !_hasFavoriteEntries(
                  people: _scopedFavoritePeople(favoriteData.people),
                  companies: companiesData.companies,
                  publishers: const [],
                )) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 132),
                children: [
                  EmptyState(
                    title: loggedIn ? 'No lists yet' : 'Nothing here',
                    message: loggedIn
                        ? 'Create personal lists to group movies your own way. '
                            'You can also favorite cast from movie pages.'
                        : 'Sign in to view your lists and favorite people.',
                    icon: Icons.list_alt_outlined,
                  ),
                  if (loggedIn) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _createList(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Create first list'),
                    ),
                  ],
                ],
              );
            }

            if (hasSearch &&
                filteredLists.isEmpty &&
                !_hasFavoriteEntries(
                  people: filteredPeople,
                  companies: filteredCompanies,
                  publishers: const [],
                )) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 16, librarySearchHorizontalInset, 132),
                children: [
                  _searchField(),
                  const SizedBox(height: 24),
                  const EmptyState(
                    title: 'No matches',
                    message: 'Nothing matches your search.',
                    icon: Icons.search_off_outlined,
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 16, librarySearchHorizontalInset, 132),
              children: [
                _searchField(),
                const SizedBox(height: 12),
                ..._libraryFavoritesSection(
                  context: context,
                  ref: ref,
                  favoriteAsync: favoriteAsync,
                  filteredPeople: filteredPeople,
                  companiesAsync: companiesAsync,
                  filteredCompanies: filteredCompanies,
                  filteredPublishers: const [],
                ),
                Text(
                  'Movie lists',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < filteredLists.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  CustomListCard(
                    list: filteredLists[i],
                    onTap: () => context.push(
                      '${mediaScope.libraryBasePath}/lists/${filteredLists[i].id}',
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.personalLists,
        mediaScope: mediaScope,
      ),
    );
  }
}
