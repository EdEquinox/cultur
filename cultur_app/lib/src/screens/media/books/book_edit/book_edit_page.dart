import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/books/book_edit_models.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail_person.dart';
import 'package:yamtrack/src/models/catalog/catalog_link.dart';
import 'package:yamtrack/src/providers/catalog_detail_providers.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/media/books/book_edit/widgets/book_edit_hero.dart';
import 'package:yamtrack/src/screens/media/books/book_edit/widgets/book_edit_search_sheet.dart';
import 'package:yamtrack/src/screens/media/books/book_edit/widgets/book_edit_sync_icon.dart';
import 'package:yamtrack/src/screens/media/books/book_edit/widgets/book_edit_sync_popover.dart';
import 'package:yamtrack/src/screens/widgets/media_detail_links_section.dart';
import 'package:yamtrack/src/screens/widgets/movie_crew_chip.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

String _normalizeFieldSource(String provider) {
  final index = provider.indexOf(':');
  if (index > 0) {
    return provider.substring(0, index);
  }
  return provider;
}

class _PendingFieldEdit {
  const _PendingFieldEdit({
    required this.displayValue,
    required this.source,
    this.value,
    this.metadataPatch,
  });

  final String displayValue;
  final String source;
  final Object? value;
  final Map<String, dynamic>? metadataPatch;
}

class BookEditPage extends ConsumerStatefulWidget {
  const BookEditPage({required this.mediaId, super.key});

  final String mediaId;

  @override
  ConsumerState<BookEditPage> createState() => _BookEditPageState();
}

class _BookEditPageState extends ConsumerState<BookEditPage> {
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  BookEditFieldsResponse? _schema;
  BookEditSearchHit? _lookup;
  final Map<String, _PendingFieldEdit> _pending = {};

  @override
  void initState() {
    super.initState();
    _loadSchema();
  }

  Future<void> _loadSchema() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final payload = await client.getJson('/catalog/books/${widget.mediaId}/edit');
      if (!mounted) {
        return;
      }
      setState(() {
        _schema = BookEditFieldsResponse.fromJson(payload);
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

  BookEditFieldInfo? _field(String key) {
    final schema = _schema;
    if (schema == null) {
      return null;
    }
    for (final field in schema.fields) {
      if (field.key == key) {
        return field;
      }
    }
    return null;
  }

  String _displayFor(String key, {String fallback = ''}) {
    final pending = _pending[key];
    if (pending != null) {
      return pending.displayValue;
    }
    return _field(key)?.currentValue ?? fallback;
  }

  bool _isPending(String key) => _pending.containsKey(key);

  List<String> _splitList(String raw) {
    return raw
        .split(RegExp(r'[,;]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  String _pagesLabel(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return '';
    }
    if (text.toLowerCase().contains('pp')) {
      return text;
    }
    return '$text pp.';
  }

  String _authorsHeroLabel() {
    final names = _splitList(_displayFor('authors'));
    if (names.isEmpty) {
      return '';
    }
    return names.take(2).join(', ');
  }

  List<CatalogLink> _linkFields() {
    final links = <CatalogLink>[];
    final porbase = _displayFor('porbaseUrl').trim();
    if (porbase.startsWith('http')) {
      links.add(CatalogLink(label: 'PORBASE', url: porbase));
    }
    final hardcover = _displayFor('hardcoverUrl').trim();
    if (hardcover.startsWith('http')) {
      links.add(CatalogLink(label: 'Hardcover', url: hardcover));
    }
    final openLibrary = _displayFor('openLibraryUrl').trim();
    if (openLibrary.startsWith('http')) {
      links.add(CatalogLink(label: 'Open Library', url: openLibrary));
    }
    return links;
  }

  Future<void> _pickLookupSource() async {
    final hit = await showModalBottomSheet<BookEditSearchHit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const BookEditSearchSheet(),
    );
    if (hit == null || !mounted) {
      return;
    }
    setState(() => _lookup = hit);
  }

  Future<void> _applyOption(BookEditFieldInfo field, BookFieldOption selected) async {
    if (selected.provider == 'manual' || selected.displayValue.isEmpty) {
      await _editManual(field);
      return;
    }
    setState(() {
      _pending[field.key] = _PendingFieldEdit(
        displayValue: selected.displayValue,
        source: _normalizeFieldSource(selected.provider),
        value: selected.value,
        metadataPatch: selected.metadataPatch,
      );
    });
  }

  Future<void> _syncField(BookEditFieldInfo field) async {
    final selected = await showBookEditSyncPopover(
      context,
      ref,
      mediaId: widget.mediaId,
      field: field,
      lookup: _lookup,
    );
    if (selected == null || !mounted) {
      return;
    }
    await _applyOption(field, selected);
  }

  Future<void> _editManual(BookEditFieldInfo field) async {
    final controller = TextEditingController(text: _displayFor(field.key));
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit ${field.label}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: field.multiline ? 10 : 1,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _pending[field.key] = _PendingFieldEdit(
        displayValue: result.trim(),
        source: 'manual',
        value: result.trim(),
      );
    });
  }

  void _editField(String key) {
    final field = _field(key);
    if (field == null) {
      return;
    }
    _editManual(field);
  }

  void _syncFieldKey(String key) {
    final field = _field(key);
    if (field == null) {
      return;
    }
    _syncField(field);
  }

  Future<void> _save() async {
    if (_pending.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No changes to save.')),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final fields = <String, dynamic>{};
      final fieldSources = <String, String>{};
      final metadataPatches = <Map<String, dynamic>>[];

      for (final entry in _pending.entries) {
        final pending = entry.value;
        fields[entry.key] = pending.value ?? pending.displayValue;
        fieldSources[entry.key] = pending.source;
        if (pending.metadataPatch != null && pending.metadataPatch!.isNotEmpty) {
          metadataPatches.add(pending.metadataPatch!);
        }
      }

      final client = ref.read(apiClientProvider);
      await client.patchJson(
        '/catalog/books/${widget.mediaId}',
        data: {
          'fields': fields,
          'fieldSources': fieldSources,
          'metadataPatches': metadataPatches,
        },
      );

      final username = ref.read(authControllerProvider).asData?.value.session?.username;
      ref.invalidate(
        catalogDetailProvider(
          CatalogDetailRequest(
            mediaId: widget.mediaId,
            username: username,
            kind: CatalogDetailKind.book,
          ),
        ),
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Book updated.')),
      );
      context.pop(true);
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final schema = _schema;

    return Scaffold(
      extendBody: true,
      appBar: CulturAppBar(
        additionalActions: [
          IconButton(
            tooltip: 'Catalog source for sync',
            onPressed: _pickLookupSource,
            icon: Badge(
              isLabelVisible: _lookup != null,
              smallSize: 8,
              child: const Icon(Icons.search),
            ),
          ),
          const SizedBox(width: 4),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Save',
              onPressed: _pending.isEmpty ? null : _save,
              style: IconButton.styleFrom(
                side: BorderSide(
                  color: scheme.onSurface.withValues(alpha: _pending.isEmpty ? 0.25 : 0.9),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(error: _error!, onRetry: _loadSchema)
              : schema == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                      children: [
                        if (_lookup != null) ...[
                          Text(
                            'Sync uses: ${_lookup!.sourceLabel} — ${_lookup!.title}',
                            style: CulturCatalogTypography.listMeta(theme, scheme),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                        ],
                        BookEditHero(
                          imageUrl: _displayFor('imageUrl'),
                          title: _displayFor('title'),
                          authorsLabel: _authorsHeroLabel(),
                          year: _displayFor('firstPublishYear'),
                          pages: _pagesLabel(_displayFor('pageCount')),
                          language: _displayFor('bookLanguage'),
                          isbn: _displayFor('isbn'),
                          titleHighlighted: _isPending('title'),
                          authorsHighlighted: _isPending('authors'),
                          onTitleTap: () => _editField('title'),
                          onTitleSync: () => _syncFieldKey('title'),
                          onAuthorsTap: () => _editField('authors'),
                          onAuthorsSync: () => _syncFieldKey('authors'),
                          onYearTap: () => _editField('firstPublishYear'),
                          onYearSync: () => _syncFieldKey('firstPublishYear'),
                          onPagesTap: () => _editField('pageCount'),
                          onPagesSync: () => _syncFieldKey('pageCount'),
                          onLanguageTap: () => _editField('bookLanguage'),
                          onLanguageSync: () => _syncFieldKey('bookLanguage'),
                          onIsbnTap: () => _editField('isbn'),
                          onIsbnSync: () => _syncFieldKey('isbn'),
                        ),
                        if (_field('imageUrl') != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _editField('imageUrl'),
                              icon: const Icon(Icons.image_outlined, size: 18),
                              label: Text(
                                _isPending('imageUrl') ? 'Cover updated' : 'Edit cover URL',
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _EditableChipSection(
                          label: 'Authors',
                          names: _splitList(_displayFor('authors')),
                          highlighted: _isPending('authors'),
                          onEdit: () => _editField('authors'),
                          onSync: () => _syncFieldKey('authors'),
                        ),
                        if (_displayFor('publisher').trim().isNotEmpty ||
                            _field('publisher') != null) ...[
                          const SizedBox(height: 16),
                          _EditableChipSection(
                            label: 'Publisher',
                            names: _splitList(_displayFor('publisher')),
                            highlighted: _isPending('publisher'),
                            onEdit: () => _editField('publisher'),
                            onSync: () => _syncFieldKey('publisher'),
                          ),
                        ],
                        if (_displayFor('subjects').trim().isNotEmpty ||
                            _field('subjects') != null) ...[
                          const SizedBox(height: 16),
                          _EditableChipSection(
                            label: 'Subjects / tags',
                            names: _splitList(_displayFor('subjects')),
                            highlighted: _isPending('subjects'),
                            onEdit: () => _editField('subjects'),
                            onSync: () => _syncFieldKey('subjects'),
                          ),
                        ],
                        if (_displayFor('description').trim().isNotEmpty ||
                            _field('description') != null) ...[
                          const SizedBox(height: 16),
                          _EditableDescriptionBlock(
                            text: _displayFor('description'),
                            highlighted: _isPending('description'),
                            onTap: () => _editField('description'),
                            onSync: () => _syncFieldKey('description'),
                          ),
                        ],
                        const SizedBox(height: 24),
                        MediaDetailLinksSection(
                          links: _linkFields(),
                          onOpenLink: (_) {},
                        ),
                        if (_field('porbaseUrl') != null ||
                            _field('hardcoverUrl') != null ||
                            _field('openLibraryUrl') != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (_field('porbaseUrl') != null)
                                OutlinedButton.icon(
                                  onPressed: () => _syncFieldKey('porbaseUrl'),
                                  icon: const Icon(Icons.sync, size: 16),
                                  label: const Text('PORBASE link'),
                                ),
                              if (_field('hardcoverUrl') != null)
                                OutlinedButton.icon(
                                  onPressed: () => _syncFieldKey('hardcoverUrl'),
                                  icon: const Icon(Icons.sync, size: 16),
                                  label: const Text('Hardcover link'),
                                ),
                              if (_field('openLibraryUrl') != null)
                                OutlinedButton.icon(
                                  onPressed: () => _syncFieldKey('openLibraryUrl'),
                                  icon: const Icon(Icons.sync, size: 16),
                                  label: const Text('Open Library link'),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
    );
  }
}

class _EditableChipSection extends StatelessWidget {
  const _EditableChipSection({
    required this.label,
    required this.names,
    required this.highlighted,
    required this.onEdit,
    required this.onSync,
  });

  final String label;
  final List<String> names;
  final bool highlighted;
  final VoidCallback onEdit;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: CulturCatalogTypography.mutedSectionTitle(theme, scheme),
              ),
            ),
            BookEditSyncIcon(onPressed: onSync),
          ],
        ),
        const SizedBox(height: 8),
        Material(
          color: highlighted
              ? scheme.primaryContainer.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: names.isEmpty
                  ? Text(
                      'Tap to add',
                      style: CulturCatalogTypography.bodyText(theme, scheme),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final name in names)
                          MovieCrewChip(
                            person: CatalogDetailPerson(name: name, role: 'Author'),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditableDescriptionBlock extends StatelessWidget {
  const _EditableDescriptionBlock({
    required this.text,
    required this.highlighted,
    required this.onTap,
    required this.onSync,
  });

  final String text;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Stack(
      children: [
        Material(
          color: highlighted
              ? scheme.primaryContainer.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.only(top: 28, right: 4, bottom: 4, left: 4),
              child: Text(
                text.isEmpty ? 'Tap to add description' : text,
                style: CulturCatalogTypography.bodyText(theme, scheme),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: BookEditSyncIcon(onPressed: onSync),
        ),
      ],
    );
  }
}
