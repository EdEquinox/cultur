import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/providers/catalog_browse_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_list_row.dart';

Future<String?> showGameResolvePendingSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String pendingMediaId,
  required String username,
  required String initialQuery,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _GameResolvePendingSheet(
      pendingMediaId: pendingMediaId,
      username: username,
      initialQuery: initialQuery,
    ),
  );
}

class _GameResolvePendingSheet extends ConsumerStatefulWidget {
  const _GameResolvePendingSheet({
    required this.pendingMediaId,
    required this.username,
    required this.initialQuery,
  });

  final String pendingMediaId;
  final String username;
  final String initialQuery;

  @override
  ConsumerState<_GameResolvePendingSheet> createState() => _GameResolvePendingSheetState();
}

class _GameResolvePendingSheetState extends ConsumerState<_GameResolvePendingSheet> {
  late final TextEditingController _queryController;
  late String _submittedQuery;
  bool _isResolving = false;

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
      final out = await client.postJson(
        '/catalog/games/${widget.pendingMediaId}/resolve-pending',
        data: {
          'username': widget.username,
          'pendingMediaId': widget.pendingMediaId,
          'igdbExternalId': item.externalId,
        },
      );
      final resolvedId = out['resolvedMediaId']?.toString();
      if (!mounted) {
        return;
      }
      if (resolvedId == null || resolvedId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not link game — missing resolved id.')),
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
    final results = ref.watch(gamesProvider(request));

    final maxListHeight = MediaQuery.sizeOf(context).height * 0.45;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Link to IGDB game',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Pick the correct match. Your status, score, and notes stay on this entry. '
            'You can paste an IGDB link or slug (e.g. agatha-christie-the-abc-murders--1).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _queryController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Title, IGDB URL, or slug…',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  setState(() => _submittedQuery = _queryController.text.trim());
                },
              ),
            ),
            onSubmitted: (value) => setState(() => _submittedQuery = value.trim()),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: maxListHeight,
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorState(
                error: error,
                onRetry: () => ref.invalidate(gamesProvider(request)),
              ),
              data: (data) {
                if (data.items.isEmpty) {
                  return const EmptyState(
                    title: 'No results',
                    message:
                        'Try fewer words, an IGDB game or bundle URL, or the slug from the address bar.',
                    icon: Icons.search_off_outlined,
                  );
                }
                return ListView.separated(
                  itemCount: data.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = data.items[index];
                    if (item.isCatalogPending) {
                      return const SizedBox.shrink();
                    }
                    return CulturCatalogListRow(
                      item: item,
                      onTap: _isResolving ? null : () => _resolve(item),
                    );
                  },
                );
              },
            ),
          ),
          if (_isResolving) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}
