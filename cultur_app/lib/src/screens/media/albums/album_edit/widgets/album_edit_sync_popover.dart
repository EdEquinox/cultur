import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/books/book_edit_models.dart';
import 'package:yamtrack/src/screens/media/albums/album_edit/widgets/album_field_options_loader.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class AlbumEditSyncPopover extends ConsumerStatefulWidget {
  const AlbumEditSyncPopover({
    required this.mediaId,
    required this.field,
    this.lookup,
    super.key,
  });

  final String mediaId;
  final BookEditFieldInfo field;
  final BookEditSearchHit? lookup;

  @override
  ConsumerState<AlbumEditSyncPopover> createState() => _AlbumEditSyncPopoverState();
}

class _AlbumEditSyncPopoverState extends ConsumerState<AlbumEditSyncPopover> {
  bool _loading = true;
  BookFieldOptionsResponse? _options;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final options = await loadAlbumFieldOptions(
        ref,
        mediaId: widget.mediaId,
        field: widget.field,
        lookup: widget.lookup,
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

  Color _providerAccent(BuildContext context, String provider) {
    final scheme = Theme.of(context).colorScheme;
    final base = provider.contains(':') ? provider.split(':').first : provider;
    return switch (base) {
      'lastfm' => const Color(0xFFD51007),
      'musicbrainz' => const Color(0xFFBA478F),
      'current' => scheme.outline,
      _ => scheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final options = _options;

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Could not load options', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Text(widget.field.label, style: theme.textTheme.titleSmall),
                      ),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          children: [
                            for (final option in options?.options ?? <BookFieldOption>[])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _SyncOptionTile(
                                  option: option,
                                  accent: _providerAccent(context, option.provider),
                                  multiline: widget.field.multiline,
                                  onTap: () => Navigator.pop(context, option),
                                ),
                              ),
                            ListTile(
                              dense: true,
                              leading: Icon(Icons.edit_outlined, color: scheme.onSurfaceVariant),
                              title: const Text('Type custom value'),
                              onTap: () => Navigator.pop(
                                context,
                                const BookFieldOption(
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

class _SyncOptionTile extends StatelessWidget {
  const _SyncOptionTile({
    required this.option,
    required this.accent,
    required this.multiline,
    required this.onTap,
  });

  final BookFieldOption option;
  final Color accent;
  final bool multiline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = option.displayValue.trim();

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                albumProviderLabel(option.provider),
                style: CulturCatalogTypography.listMeta(theme, scheme),
              ),
              if (value.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: multiline ? 6 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: CulturCatalogTypography.bodyText(theme, scheme),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<BookFieldOption?> showAlbumEditSyncPopover(
  BuildContext context,
  WidgetRef ref, {
  required String mediaId,
  required BookEditFieldInfo field,
  BookEditSearchHit? lookup,
}) {
  return showDialog<BookFieldOption>(
    context: context,
    builder: (dialogContext) => AlbumEditSyncPopover(
      mediaId: mediaId,
      field: field,
      lookup: lookup,
    ),
  );
}
