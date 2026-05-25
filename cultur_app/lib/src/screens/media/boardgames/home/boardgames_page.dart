import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/catalog/catalog_category.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/catalog_browse_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/game_home_poster_card.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/home_categories.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';

class BoardgamesPage extends ConsumerStatefulWidget {
  const BoardgamesPage({
    this.initialQuery = '',
    this.initialSection = '',
    super.key,
  });

  final String initialQuery;
  final String initialSection;

  @override
  ConsumerState<BoardgamesPage> createState() => _BoardgamesPageState();
}

class _BoardgamesPageState extends ConsumerState<BoardgamesPage> {
  late final TextEditingController _queryController;
  late String _submittedQuery;
  late String _submittedSection;

  @override
  void initState() {
    super.initState();
    _submittedQuery = widget.initialQuery.trim();
    _submittedSection = normalizedCatalogSection(
      CatalogBrowseKind.boardgames,
      widget.initialSection.trim(),
    );
    _queryController = TextEditingController(text: _submittedQuery);
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _submitSearch() {
    setState(() {
      _submittedQuery = _queryController.text.trim();
      _submittedSection = 'popular';
    });
  }

  CatalogBrowseRequest get _browseRequest => CatalogBrowseRequest(
        section: _submittedQuery.isNotEmpty ? 'popular' : _submittedSection,
        query: _submittedQuery,
      );

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(boardgamesProvider(_browseRequest));
    final heading = _submittedQuery.isNotEmpty
        ? 'Results for “$_submittedQuery”'
        : 'Popular on BGG';

    return Scaffold(
      extendBody: true,
      appBar: const CulturAppBar(),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(boardgamesProvider(_browseRequest).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 132),
          children: [
            LibraryItemSearchField(
              controller: _queryController,
              hintText: 'Search board games on BGG…',
              onChanged: (_) {},
              onSubmitted: (_) => _submitSearch(),
              trailing: IconButton(
                tooltip: 'Search',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                onPressed: _submitSearch,
                icon: const Icon(Icons.search, size: 18),
              ),
            ),
            const SizedBox(height: 16),
            Text(heading, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            results.when(
              loading: () => const Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )),
              error: (error, stackTrace) => ErrorState(
                error: error,
                onRetry: () => ref.invalidate(boardgamesProvider(_browseRequest)),
              ),
              data: (data) {
                if (data.items.isEmpty) {
                  return EmptyState(
                    title: 'No board games',
                    message: _submittedQuery.isNotEmpty
                        ? 'Try another search term.'
                        : 'Nothing to show from BGG right now.',
                    icon: Icons.casino_outlined,
                  );
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.42,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: data.items.length,
                  itemBuilder: (context, index) {
                    final item = data.items[index];
                    return _BoardgameGridTile(item: item);
                  },
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: const FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: LibraryMediaScope.boardgame,
      ),
    );
  }
}

class _BoardgameGridTile extends StatelessWidget {
  const _BoardgameGridTile({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    return GameHomePosterCard(
      catalogItem: item,
      onTap: () => context.push(catalogItemDetailPath(item)),
    );
  }
}
