import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/books/book_edit_models.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';

/// Search Hardcover and link or enrich a book (pending resolve or metadata apply).
Future<String?> showBookHardcoverResolveSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String mediaId,
  required String username,
  required String initialQuery,
  required bool isPending,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _BookHardcoverResolveSheet(
      mediaId: mediaId,
      username: username,
      initialQuery: initialQuery,
      isPending: isPending,
    ),
  );
}

class _BookHardcoverResolveSheet extends ConsumerStatefulWidget {
  const _BookHardcoverResolveSheet({
    required this.mediaId,
    required this.username,
    required this.initialQuery,
    required this.isPending,
  });

  final String mediaId;
  final String username;
  final String initialQuery;
  final bool isPending;

  @override
  ConsumerState<_BookHardcoverResolveSheet> createState() => _BookHardcoverResolveSheetState();
}

class _BookHardcoverResolveSheetState extends ConsumerState<_BookHardcoverResolveSheet> {
  late final TextEditingController _queryController;
  bool _loading = false;
  List<BookEditSearchHit> _results = const [];
  String? _error;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/books/edit-search',
        queryParameters: {'q': query, 'limit': 24, 'sources': 'hardcover'},
      );
      if (!mounted) {
        return;
      }
      final response = BookEditSearchResponse.fromJson(payload);
      setState(() {
        _results = response.results.where((h) => h.source == 'hardcover').toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
      showApiErrorSnackBar(context, error);
    }
  }

  Future<void> _apply(BookEditSearchHit hit) async {
    if (_isApplying) {
      return;
    }
    setState(() => _isApplying = true);
    try {
      final client = ref.read(apiClientProvider);
      final Map<String, dynamic> body = {
        'username': widget.username,
        'source': hit.source,
        'externalId': hit.externalId,
        if (hit.isbn != null && hit.isbn!.isNotEmpty) 'isbn': hit.isbn,
        'title': hit.title,
        if (hit.authors != null && hit.authors!.isNotEmpty) 'authors': hit.authors,
      };

      final Map<String, dynamic> out;
      if (widget.isPending) {
        out = await client.postJson(
          '/catalog/books/${widget.mediaId}/resolve-pending',
          data: {
            'username': widget.username,
            'pendingMediaId': widget.mediaId,
            'resolvedSource': hit.source,
            'resolvedExternalId': hit.externalId,
          },
        );
      } else {
        out = await client.postJson(
          '/catalog/books/${widget.mediaId}/apply-lookup',
          data: body,
        );
      }

      final resolvedId = (out['resolvedMediaId'] ?? out['mediaId'])?.toString();
      if (!mounted) {
        return;
      }
      if (resolvedId == null || resolvedId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not link book — missing id in response.')),
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
        setState(() => _isApplying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.45;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Link from Hardcover',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            widget.isPending
                ? 'Pick the correct Hardcover edition. Your reading status and notes stay on this entry.'
                : 'Pick a Hardcover match to refresh title, cover, and metadata on this book.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Title, author, or ISBN',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _loading ? null : _search,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: maxListHeight,
            child: _loading && _results.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? const EmptyState(
                        title: 'No Hardcover results',
                        message: 'Try another title, author name, or ISBN.',
                        icon: Icons.search_off_outlined,
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final hit = _results[index];
                          return ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                            leading: hit.imageUrl != null && hit.imageUrl!.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(
                                      hit.imageUrl!,
                                      width: 40,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.menu_book_outlined),
                                    ),
                                  )
                                : const Icon(Icons.menu_book_outlined),
                            title: Text(
                              hit.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (hit.authors != null && hit.authors!.isNotEmpty) hit.authors,
                                if (hit.isbn != null && hit.isbn!.isNotEmpty) 'ISBN ${hit.isbn}',
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: _isApplying ? null : () => _apply(hit),
                          );
                        },
                      ),
          ),
          if (_isApplying) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}
