import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/movie/movie_catalog_detail.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

import 'rating_stars_row.dart';

class MarkWatchedSheetResult {
  const MarkWatchedSheetResult({
    this.completedAtUtc,
    this.score,
    this.removeFromList = false,
  });

  final DateTime? completedAtUtc;
  final double? score;
  final bool removeFromList;
}

/// Copy for mark-watched / mark-listened bottom sheets.
class MarkWatchedSheetLabels {
  const MarkWatchedSheetLabels({
    required this.sheetTitle,
    required this.ratePrompt,
    required this.submitLabel,
    required this.submitIcon,
    required this.fallbackIcon,
    required this.removeSheetTitle,
    required this.removePrompt,
    this.editSheetTitle,
    this.editSubmitLabel,
    this.removeFromListLabel,
  });

  final String sheetTitle;
  final String ratePrompt;
  final String submitLabel;
  final IconData submitIcon;
  final IconData fallbackIcon;
  final String removeSheetTitle;
  final String removePrompt;
  final String? editSheetTitle;
  final String? editSubmitLabel;
  final String? removeFromListLabel;

  String get effectiveEditSheetTitle => editSheetTitle ?? removeSheetTitle;

  String get effectiveEditSubmitLabel => editSubmitLabel ?? 'Save';

  String get effectiveRemoveFromListLabel =>
      removeFromListLabel ?? 'Remove from list';

  static const movie = MarkWatchedSheetLabels(
    sheetTitle: 'Mark as watched',
    ratePrompt: 'Rate movie?',
    submitLabel: 'Mark as watched',
    submitIcon: Icons.remove_red_eye_outlined,
    fallbackIcon: Icons.movie_outlined,
    removeSheetTitle: 'Watched',
    removePrompt: 'Remove this title from your watched list?',
  );

  static const album = MarkWatchedSheetLabels(
    sheetTitle: 'Mark as listened',
    ratePrompt: 'Rate album?',
    submitLabel: 'Mark as listened',
    submitIcon: Icons.headphones_outlined,
    fallbackIcon: Icons.album_outlined,
    removeSheetTitle: 'Listened',
    removePrompt: 'Remove this album from your listened list?',
    editSheetTitle: 'Listened',
    editSubmitLabel: 'Save',
    removeFromListLabel: 'Remove from listened',
  );
}

enum _WatchedWhenOption { now, custom, unknown }

class MarkWatchedSheet extends StatefulWidget {
  const MarkWatchedSheet({
    super.key,
    required this.detail,
    this.labels = MarkWatchedSheetLabels.movie,
    this.isEditing = false,
  })  : media = null,
        tracking = null;

  const MarkWatchedSheet.forCatalog({
    super.key,
    required this.media,
    this.tracking,
    this.labels = MarkWatchedSheetLabels.movie,
    this.isEditing = false,
  }) : detail = null;

  final MovieCatalogDetail? detail;
  final CatalogItem? media;
  final TrackingItem? tracking;
  final MarkWatchedSheetLabels labels;
  final bool isEditing;

  CatalogItem get catalogMedia => detail?.media ?? media!;

  @override
  State<MarkWatchedSheet> createState() => _MarkWatchedSheetState();
}

class _MarkWatchedSheetState extends State<MarkWatchedSheet> {
  _WatchedWhenOption _when = _WatchedWhenOption.now;
  late DateTime _customLocal;
  int _stars = 0;

  @override
  void initState() {
    super.initState();
    _customLocal = DateTime.now();
    if (widget.isEditing) {
      final completedAt = widget.tracking?.completedAt;
      if (completedAt == null) {
        _when = _WatchedWhenOption.unknown;
      } else {
        _when = _WatchedWhenOption.custom;
        _customLocal = completedAt.toLocal();
      }
      final score = widget.tracking?.score;
      if (score != null && score > 0) {
        _stars = score.round().clamp(0, 10);
      }
    }
  }

  Future<void> _pickDate() async {
    if (_when != _WatchedWhenOption.custom) {
      setState(() {
        _when = _WatchedWhenOption.custom;
        _customLocal = DateTime.now();
      });
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(
        _customLocal.year,
        _customLocal.month,
        _customLocal.day,
      ),
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _customLocal = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _customLocal.hour,
        _customLocal.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    if (_when != _WatchedWhenOption.custom) {
      setState(() {
        _when = _WatchedWhenOption.custom;
        _customLocal = DateTime.now();
      });
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_customLocal),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _customLocal = DateTime(
        _customLocal.year,
        _customLocal.month,
        _customLocal.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _submit() {
    final DateTime? completedUtc = switch (_when) {
      _WatchedWhenOption.now => DateTime.now().toUtc(),
      _WatchedWhenOption.custom => DateTime(
        _customLocal.year,
        _customLocal.month,
        _customLocal.day,
        _customLocal.hour,
        _customLocal.minute,
      ).toUtc(),
      _WatchedWhenOption.unknown => null,
    };
    final score = _stars > 0 ? _stars.toDouble() : null;
    Navigator.of(
      context,
    ).pop(MarkWatchedSheetResult(completedAtUtc: completedUtc, score: score));
  }

  void _submitRemove() {
    Navigator.of(context).pop(const MarkWatchedSheetResult(removeFromList: true));
  }

  Widget _whenTile({
    required String title,
    required _WatchedWhenOption value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _when == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => setState(() => _when = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                Expanded(child: Text(title)),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = widget.catalogMedia;
    final labels = widget.labels;
    final loc = MaterialLocalizations.of(context);
    final customDateLabel = loc.formatMediumDate(
      DateTime(_customLocal.year, _customLocal.month, _customLocal.day),
    );
    final customTimeLabel = TimeOfDay.fromDateTime(_customLocal).format(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceContainerHigh,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.isEditing
                        ? labels.effectiveEditSheetTitle
                        : labels.sheetTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 28,
                        height: 40,
                        child: media.imageUrl != null && media.imageUrl!.isNotEmpty
                            ? Image.network(
                                media.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return ColoredBox(
                                    color: scheme.surfaceContainerHigh,
                                    child: Icon(
                                      labels.fallbackIcon,
                                      size: 18,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  );
                                },
                              )
                            : ColoredBox(
                                color: scheme.surfaceContainerHigh,
                                child: Icon(
                                  labels.fallbackIcon,
                                  size: 18,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        media.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DateTimeFieldChip(
                    label: _when == _WatchedWhenOption.unknown
                        ? '—'
                        : _when == _WatchedWhenOption.now
                        ? loc.formatMediumDate(DateTime.now())
                        : customDateLabel,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateTimeFieldChip(
                    label: _when == _WatchedWhenOption.unknown
                        ? '—'
                        : _when == _WatchedWhenOption.now
                        ? TimeOfDay.now().format(context)
                        : customTimeLabel,
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _whenTile(title: 'Now', value: _WatchedWhenOption.now),
            _whenTile(title: 'Custom date', value: _WatchedWhenOption.custom),
            _whenTile(title: 'Unknown date', value: _WatchedWhenOption.unknown),
            const SizedBox(height: 20),
            Text(
              labels.ratePrompt,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            RatingStarsRow(
              selectedCount: _stars,
              onChanged: (v) => setState(() => _stars = v),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              onPressed: _submit,
              icon: Icon(labels.submitIcon),
              label: Text(
                widget.isEditing ? labels.effectiveEditSubmitLabel : labels.submitLabel,
              ),
            ),
            if (widget.isEditing) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: _submitRemove,
                child: Text(labels.effectiveRemoveFromListLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DateTimeFieldChip extends StatelessWidget {
  const _DateTimeFieldChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class RemoveWatchedSheet extends StatelessWidget {
  const RemoveWatchedSheet({
    super.key,
    required this.detail,
    this.labels = MarkWatchedSheetLabels.movie,
  }) : media = null;

  const RemoveWatchedSheet.forCatalog({
    super.key,
    required this.media,
    this.labels = MarkWatchedSheetLabels.movie,
  }) : detail = null;

  final MovieCatalogDetail? detail;
  final CatalogItem? media;
  final MarkWatchedSheetLabels labels;

  CatalogItem get catalogMedia => detail?.media ?? media!;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = catalogMedia;
    final labels = this.labels;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceContainerHigh,
                  ),
                ),
                Expanded(
                  child: Text(
                    labels.removeSheetTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 28,
                        height: 40,
                        child: media.imageUrl != null && media.imageUrl!.isNotEmpty
                            ? Image.network(
                                media.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return ColoredBox(
                                    color: scheme.surfaceContainerHigh,
                                    child: Icon(
                                      labels.fallbackIcon,
                                      size: 18,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  );
                                },
                              )
                            : ColoredBox(
                                color: scheme.surfaceContainerHigh,
                                child: Icon(
                                  labels.fallbackIcon,
                                  size: 18,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        media.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              labels.removePrompt,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Remove'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
