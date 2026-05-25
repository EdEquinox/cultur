import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/screens/home/home_shelf_list_body.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart'
    show LibraryItemSearchField, librarySearchHorizontalInset;
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';

/// Full list for a catalog home shelf (opened from the chevron on category home).
class HomeShelfListPage extends ConsumerStatefulWidget {
  const HomeShelfListPage({
    super.key,
    required this.scope,
    required this.shelf,
  });

  /// `tv`, `movies`, or `games`
  final String scope;

  /// `continue-watching` | `next-to-watch` | `upcoming` | `events`
  final String shelf;

  static const int backendShelfCap = 24;

  @override
  ConsumerState<HomeShelfListPage> createState() => _HomeShelfListPageState();
}

class _HomeShelfListPageState extends ConsumerState<HomeShelfListPage> {
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

  String get _pageTitle {
    switch ('${widget.scope}:${widget.shelf}') {
      case 'tv:continue-watching':
        return 'Continue watching';
      case 'tv:next-to-watch':
      case 'movies:next-to-watch':
        return 'Next to watch';
      case 'tv:upcoming':
      case 'movies:upcoming':
        return 'Upcoming';
      case 'games:events':
        return 'Events';
      default:
        return 'Shelf';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).asData?.value;
    final username = auth?.session?.username ?? '';

    if (username.isEmpty) {
      return Scaffold(
        appBar: const CulturAppBar(),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Sign in to see this list.'),
          ),
        ),
      );
    }

    final key = '${widget.scope}:${widget.shelf}';
    if (!_isSupported(key)) {
      return Scaffold(
        appBar: const CulturAppBar(),
        body: const Center(child: Text('This shelf is not available here.')),
      );
    }

    return Scaffold(
      appBar: const CulturAppBar(),
      body: Column(
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
              hintText: 'Search in ${_pageTitle.toLowerCase()}…',
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: HomeShelfListBody(
              scope: widget.scope,
              shelf: widget.shelf,
              username: username,
              searchQuery: _searchController.text,
            ),
          ),
        ],
      ),
    );
  }

  bool _isSupported(String key) {
    return const {
      'tv:continue-watching',
      'tv:next-to-watch',
      'tv:upcoming',
      'movies:next-to-watch',
      'movies:upcoming',
      'games:events',
    }.contains(key);
  }

}
