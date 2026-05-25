import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/books/book_edit_models.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail_person.dart';
import 'package:yamtrack/src/models/catalog/catalog_link.dart';
import 'package:yamtrack/src/providers/albums_home_providers.dart';
import 'package:yamtrack/src/providers/catalog_detail_providers.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/media/albums/album_edit/widgets/album_edit_search_sheet.dart';
import 'package:yamtrack/src/screens/media/albums/album_edit/widgets/album_edit_sync_popover.dart';
import 'package:yamtrack/src/screens/media/books/book_edit/widgets/book_edit_sync_icon.dart';
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

class AlbumEditPage extends ConsumerStatefulWidget {
  const AlbumEditPage({required this.mediaId, super.key});

  final String mediaId;

  @override
  ConsumerState<AlbumEditPage> createState() => _AlbumEditPageState();
}

class _AlbumEditPageState extends ConsumerState<AlbumEditPage> {
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
      final payload = await client.getJson('/catalog/music/${widget.mediaId}/edit');
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

  List<CatalogLink> _linkFields() {
    final mb = _displayFor('musicbrainzUrl').trim();
    if (mb.startsWith('http')) {
      return [CatalogLink(label: 'MusicBrainz', url: mb)];
    }
    return const [];
  }

  Future<void> _pickLookupSource() async {
    final hit = await showModalBottomSheet<BookEditSearchHit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const AlbumEditSearchSheet(),
    );
    if (hit == null || !mounted) {
      return;
    }

    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update from Last.fm?'),
        content: Text(
          'Replace this album\'s saved details with:\n\n${hit.title}'
          '${hit.authors != null && hit.authors!.isNotEmpty ? '\n${hit.authors}' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Use for field sync only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update now'),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _lookup = hit);
    if (apply != true) {
      return;
    }

    setState(() => _saving = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.patchJson(
        '/catalog/music/${widget.mediaId}',
        data: {
          'fields': <String, dynamic>{},
          'lookupSource': hit.source,
          'lookupExternalId': hit.externalId,
        },
      );
      _pending.clear();
      await _loadSchema();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Album updated from Last.fm.')),
      );
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
    final selected = await showAlbumEditSyncPopover(
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
        '/catalog/music/${widget.mediaId}',
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
            kind: CatalogDetailKind.music,
          ),
        ),
      );
      if (username != null && username.isNotEmpty) {
        invalidateAlbumsHomeCaches(ref, username: username);
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Album updated.')),
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
            tooltip: 'Search MusicBrainz',
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
                            'Sync uses: Last.fm — ${_lookup!.title}',
                            style: CulturCatalogTypography.listMeta(theme, scheme),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                        ],
                        _AlbumEditHeroPreview(
                          imageUrl: _displayFor('imageUrl'),
                          title: _displayFor('title'),
                          artist: _displayFor('artist'),
                          year: _displayFor('year'),
                          titleHighlighted: _isPending('title'),
                          artistHighlighted: _isPending('artist'),
                          onTitleTap: () => _editField('title'),
                          onTitleSync: () => _syncFieldKey('title'),
                          onArtistTap: () => _editField('artist'),
                          onArtistSync: () => _syncFieldKey('artist'),
                          onYearTap: () => _editField('year'),
                          onYearSync: () => _syncFieldKey('year'),
                        ),
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
                        const SizedBox(height: 16),
                        _EditableChipSection(
                          label: 'Genres',
                          names: _splitList(_displayFor('genres')),
                          highlighted: _isPending('genres'),
                          onEdit: () => _editField('genres'),
                          onSync: () => _syncFieldKey('genres'),
                        ),
                        const SizedBox(height: 16),
                        _EditableChipSection(
                          label: 'Artists',
                          names: _splitList(_displayFor('artists')),
                          highlighted: _isPending('artists'),
                          onEdit: () => _editField('artists'),
                          onSync: () => _syncFieldKey('artists'),
                        ),
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
                        if (_field('musicbrainzUrl') != null) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => _syncFieldKey('musicbrainzUrl'),
                            icon: const Icon(Icons.sync, size: 16),
                            label: const Text('MusicBrainz link'),
                          ),
                        ],
                      ],
                    ),
    );
  }
}

class _AlbumEditHeroPreview extends StatelessWidget {
  const _AlbumEditHeroPreview({
    required this.imageUrl,
    required this.title,
    required this.artist,
    required this.year,
    required this.onTitleTap,
    required this.onTitleSync,
    required this.onArtistTap,
    required this.onArtistSync,
    required this.onYearTap,
    required this.onYearSync,
    this.titleHighlighted = false,
    this.artistHighlighted = false,
  });

  final String imageUrl;
  final String title;
  final String artist;
  final String year;
  final VoidCallback onTitleTap;
  final VoidCallback onTitleSync;
  final VoidCallback onArtistTap;
  final VoidCallback onArtistSync;
  final VoidCallback onYearTap;
  final VoidCallback onYearSync;
  final bool titleHighlighted;
  final bool artistHighlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cover = imageUrl.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 88,
            height: 88,
            child: cover.isNotEmpty
                ? Image.network(cover, fit: BoxFit.cover)
                : ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.album_outlined, color: scheme.outline),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EditableLine(
                label: 'Title',
                value: title,
                highlighted: titleHighlighted,
                onTap: onTitleTap,
                onSync: onTitleSync,
              ),
              const SizedBox(height: 10),
              _EditableLine(
                label: 'Artist',
                value: artist,
                highlighted: artistHighlighted,
                onTap: onArtistTap,
                onSync: onArtistSync,
              ),
              const SizedBox(height: 10),
              _EditableLine(
                label: 'Year',
                value: year,
                highlighted: false,
                onTap: onYearTap,
                onSync: onYearSync,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditableLine extends StatelessWidget {
  const _EditableLine({
    required this.label,
    required this.value,
    required this.highlighted,
    required this.onTap,
    required this.onSync,
  });

  final String label;
  final String value;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Material(
            color: highlighted
                ? scheme.primaryContainer.withValues(alpha: 0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: CulturCatalogTypography.listMeta(theme, scheme)),
                    Text(
                      value.isEmpty ? 'Tap to add' : value,
                      style: CulturCatalogTypography.listTitleBig(theme),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        BookEditSyncIcon(onPressed: onSync),
      ],
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
                  ? Text('Tap to add', style: CulturCatalogTypography.bodyText(theme, scheme))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final name in names)
                          MovieCrewChip(
                            person: CatalogDetailPerson(name: name, role: 'Artist'),
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
