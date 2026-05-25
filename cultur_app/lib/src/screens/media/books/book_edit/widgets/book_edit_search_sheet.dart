import 'package:flutter/material.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/books/book_edit_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Search PORBASE, Hardcover, and Open Library for a catalog record to use as lookup source.
class BookEditSearchSheet extends ConsumerStatefulWidget {
  const BookEditSearchSheet({super.key});

  @override
  ConsumerState<BookEditSearchSheet> createState() => _BookEditSearchSheetState();
}

class _BookEditSearchSheetState extends ConsumerState<BookEditSearchSheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  List<BookEditSearchHit> _results = const [];
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
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
        queryParameters: {'q': query, 'limit': 24},
      );
      if (!mounted) {
        return;
      }
      final response = BookEditSearchResponse.fromJson(payload);
      setState(() {
        _results = response.results;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Search catalog',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Find a book on PORBASE, Hardcover, or Open Library to pull field values from.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: 'Title, author, or ISBN',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
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
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final hit = _results[index];
                  return ListTile(
                    leading: hit.imageUrl != null && hit.imageUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              hit.imageUrl!,
                              width: 40,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(Icons.menu_book_outlined),
                            ),
                          )
                        : const Icon(Icons.menu_book_outlined),
                    title: Text(hit.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [
                        hit.sourceLabel,
                        if (hit.authors != null && hit.authors!.isNotEmpty) hit.authors,
                        if (hit.isbn != null && hit.isbn!.isNotEmpty) 'ISBN ${hit.isbn}',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(context, hit),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
