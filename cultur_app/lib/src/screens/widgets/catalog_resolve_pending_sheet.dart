import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/providers/catalog_browse_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_list_row.dart';

enum CatalogResolvePendingKind { game, book, movie, tv }

Future<String?> showCatalogResolvePendingSheet({
  required BuildContext context,
  required WidgetRef ref,
  required CatalogResolvePendingKind kind,
  required String pendingMediaId,
  required String username,
  required String initialQuery,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _CatalogResolvePendingSheet(
      kind: kind,
      pendingMediaId: pendingMediaId,
      username: username,
      initialQuery: initialQuery,
    ),
  );
}

class _CatalogResolvePendingSheet extends ConsumerStatefulWidget {
  const _CatalogResolvePendingSheet({
    required this.kind,
    required this.pendingMediaId,
    required this.username,
    required this.initialQuery,
  });

  final CatalogResolvePendingKind kind;
  final String pendingMediaId;
  final String username;
  final String initialQuery;

  @override
  ConsumerState<_CatalogResolvePendingSheet> createState() =>
      _CatalogResolvePendingSheetState();
}

class _CatalogResolvePendingSheetState extends ConsumerState<_CatalogResolvePendingSheet> {
  late final TextEditingController _queryController;
  late String _submittedQuery;
  bool _isResolving = false;

  String get _resolvePath => switch (widget.kind) {
        CatalogResolvePendingKind.game =>
          '/catalog/games/${widget.pendingMediaId}/resolve-pending',
        CatalogResolvePendingKind.book =>
          '/catalog/books/${widget.pendingMediaId}/resolve-pending',
        CatalogResolvePendingKind.movie =>
          '/catalog/movies/${widget.pendingMediaId}/resolve-pending',
        CatalogResolvePendingKind.tv =>
          '/catalog/tv/${widget.pendingMediaId}/resolve-pending',
      };

  String get _title => switch (widget.kind) {
        CatalogResolvePendingKind.game => 'Link to IGDB game or bundle',
        CatalogResolvePendingKind.book => 'Link to catalog book',
        CatalogResolvePendingKind.movie => 'Link to TMDB movie',
        CatalogResolvePendingKind.tv => 'Link to TMDB series',
      };

  Map<String, dynamic> _resolveBody(CatalogItem item) {
    final base = {
      'username': widget.username,
      'pendingMediaId': widget.pendingMediaId,
    };
    return switch (widget.kind) {
      CatalogResolvePendingKind.game => {
          ...base,
          'igdbExternalId': item.externalId,
        },
      CatalogResolvePendingKind.book => {
          ...base,
          'resolvedMediaId': item.id,
        },
      CatalogResolvePendingKind.movie || CatalogResolvePendingKind.tv => {
          ...base,
          'tmdbId': item.externalId,
        },
    };
  }

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _submittedQuery = widget.initialQuery.trim();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _resolve(CatalogItem item) async {
    if (_isResolving) {
      return;
    }
    setState(() => _isResolving = true);
    try {
      final client = ref.read(apiClientProvider);
      final out = await client.postJson(_resolvePath, data: _resolveBody(item));
      final resolvedId = out['resolvedMediaId']?.toString();
      if (!mounted) {
        return;
      }
      if (resolvedId == null || resolvedId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not link — missing resolved id.')),
        );
        return;
      }
      Navigator.of(context).pop(resolvedId);
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error, prefix: 'Link failed:');
      }
    } finally {
      if (mounted) {
        setState(() => _isResolving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final request = CatalogBrowseRequest(
      section: 'popular',
      query: _submittedQuery,
    );
    final results = switch (widget.kind) {
      CatalogResolvePendingKind.game => ref.watch(gamesProvider(request)),
      CatalogResolvePendingKind.book => ref.watch(booksProvider(request)),
      CatalogResolvePendingKind.movie => ref.watch(moviesProvider(request)),
      CatalogResolvePendingKind.tv => ref.watch(tvShowsProvider(request)),
    };

    final maxListHeight = MediaQuery.sizeOf(context).height * 0.45;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _queryController,
            decoration: InputDecoration(
              hintText: 'Search catalog',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _submittedQuery = _queryController.text.trim()),
              ),
            ),
            onSubmitted: (_) => setState(() => _submittedQuery = _queryController.text.trim()),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: results.when(
              loading: () => const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )),
              error: (error, _) => ErrorState(
                error: error,
                onRetry: () => setState(() {}),
              ),
              data: (data) {
                final visible = data.items.where((i) => !i.isCatalogPending).toList();
                if (visible.isEmpty) {
                  return const EmptyState(
                    title: 'No results',
                    message: 'Try another search or fewer words.',
                    icon: Icons.search_off_outlined,
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    return CulturCatalogListRow(
                      item: item,
                      onTap: _isResolving ? null : () => _resolve(item),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
