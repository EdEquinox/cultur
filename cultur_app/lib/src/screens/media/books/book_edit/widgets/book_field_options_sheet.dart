import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/books/book_edit_models.dart';
import 'package:yamtrack/src/screens/media/books/book_edit/widgets/book_field_options_loader.dart';

class BookFieldOptionsSheet extends ConsumerStatefulWidget {
  const BookFieldOptionsSheet({
    required this.mediaId,
    required this.field,
    this.lookup,
    super.key,
  });

  final String mediaId;
  final BookEditFieldInfo field;
  final BookEditSearchHit? lookup;

  @override
  ConsumerState<BookFieldOptionsSheet> createState() => _BookFieldOptionsSheetState();
}

class _BookFieldOptionsSheetState extends ConsumerState<BookFieldOptionsSheet> {
  final _searchController = TextEditingController();
  bool _loading = true;
  BookFieldOptionsResponse? _options;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions({String? search}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final options = await loadBookFieldOptions(
        ref,
        mediaId: widget.mediaId,
        field: widget.field,
        lookup: widget.lookup,
        search: search,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _options = options;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _options;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose ${widget.field.label}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'Search catalog for this field',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _loadOptions(search: _searchController.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _loading ? null : () => _loadOptions(search: _searchController.text),
                        icon: const Icon(Icons.search),
                      ),
                    ],
                  ),
                  if (widget.lookup != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Using: ${widget.lookup!.sourceLabel} — ${widget.lookup!.title}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load options.'),
              )
            else if (options != null)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final option in options.options)
                      ListTile(
                        title: Text(option.label),
                        subtitle: Text(
                          option.displayValue,
                          maxLines: options.multiline ? 8 : 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, option),
                      ),
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Type custom value'),
                      onTap: () => Navigator.pop(
                        context,
                        BookFieldOption(
                          provider: 'manual',
                          label: 'Custom',
                          displayValue: '',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
