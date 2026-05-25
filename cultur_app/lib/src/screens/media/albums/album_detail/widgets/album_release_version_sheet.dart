import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class AlbumReleaseVersionOption {
  const AlbumReleaseVersionOption({
    required this.releaseMbid,
    required this.title,
    this.format,
    this.country,
    this.released,
    this.label,
    this.catno,
    this.thumbUrl,
  });

  final String releaseMbid;
  final String title;
  final String? format;
  final String? country;
  final String? released;
  final String? label;
  final String? catno;
  final String? thumbUrl;

  String get subtitle {
    final parts = <String>[
      if (format != null && format!.isNotEmpty) format!,
      if (released != null && released!.isNotEmpty) released!,
      if (country != null && country!.isNotEmpty) country!,
      if (label != null && label!.isNotEmpty) label!,
    ];
    return parts.join(' · ');
  }
}

class AlbumReleaseVersionPick {
  const AlbumReleaseVersionPick({
    required this.version,
    this.price,
  });

  final AlbumReleaseVersionOption version;
  final String? price;
}

final albumReleaseVersionsProvider = FutureProvider.autoDispose
    .family<List<AlbumReleaseVersionOption>, String>((ref, mediaId) async {
  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson('/catalog/music/$mediaId/versions');
  final rows = payload['items'];
  if (rows is! List) {
    return const [];
  }
  return [
    for (final row in rows)
      if (row is Map)
        AlbumReleaseVersionOption(
          releaseMbid: row['discogsReleaseId']?.toString() ?? '',
          title: row['title']?.toString() ?? 'Release',
          format: row['format']?.toString(),
          country: row['country']?.toString(),
          released: row['released']?.toString(),
          label: row['label']?.toString(),
          catno: row['catno']?.toString(),
          thumbUrl: row['thumbUrl']?.toString(),
        ),
  ].where((v) => v.releaseMbid.isNotEmpty).toList();
});

Future<AlbumReleaseVersionPick?> showAlbumReleaseVersionSheet(
  BuildContext context, {
  required String mediaId,
  String? initialPrice,
}) {
  return showModalBottomSheet<AlbumReleaseVersionPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: (context) => _AlbumReleaseVersionSheet(
      mediaId: mediaId,
      initialPrice: initialPrice,
    ),
  );
}

class _AlbumReleaseVersionSheet extends ConsumerStatefulWidget {
  const _AlbumReleaseVersionSheet({
    required this.mediaId,
    this.initialPrice,
  });

  final String mediaId;
  final String? initialPrice;

  @override
  ConsumerState<_AlbumReleaseVersionSheet> createState() => _AlbumReleaseVersionSheetState();
}

class _AlbumReleaseVersionSheetState extends ConsumerState<_AlbumReleaseVersionSheet> {
  AlbumReleaseVersionOption? _selected;
  late final TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(text: widget.initialPrice ?? '');
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  void _submit() {
    final version = _selected;
    if (version == null) {
      return;
    }
    final price = _priceController.text.trim();
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      AlbumReleaseVersionPick(
        version: version,
        price: price.isEmpty ? null : price,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final versionsAsync = ref.watch(albumReleaseVersionsProvider(widget.mediaId));
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Which version do you own?',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick the pressing, then add what you paid (optional).',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            versionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load versions: $error'),
              ),
              data: (versions) {
                if (versions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Pressings are not available for Last.fm albums.'),
                  );
                }
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: versions.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final version = versions[index];
                      final selected = _selected?.releaseMbid == version.releaseMbid;
                      return ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        tileColor: selected
                            ? scheme.primaryContainer.withValues(alpha: 0.55)
                            : scheme.surfaceContainerHigh,
                        leading: version.thumbUrl != null && version.thumbUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  version.thumbUrl!,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Icon(
                                    Icons.album_outlined,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : Icon(Icons.album_outlined, color: scheme.onSurfaceVariant),
                        title: Text(
                          version.format ?? version.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: CulturCatalogTypography.gridTitle(theme),
                        ),
                        subtitle: version.subtitle.isEmpty
                            ? null
                            : Text(
                                version.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: CulturCatalogTypography.gridSubtitle(theme, scheme),
                              ),
                        trailing: selected
                            ? Icon(Icons.check_circle, color: scheme.primary)
                            : null,
                        onTap: () => setState(() => _selected = version),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Price paid',
                hintText: 'e.g. 24.90',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _selected == null ? null : _submit,
              child: const Text('Add to Owned'),
            ),
          ],
        ),
      ),
    );
  }
}
