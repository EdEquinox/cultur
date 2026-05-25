import 'package:flutter/material.dart';

/// Result of confirming “when” you watched (episode or batch).
///
/// [watchedAtUtc] `null` means omit `watchedAt` in the API (backend uses current UTC).
/// Non-null is sent as ISO-8601 and stored for the episode(s).
class EpisodeWatchedAtSubmit {
  const EpisodeWatchedAtSubmit({required this.watchedAtUtc});

  final DateTime? watchedAtUtc;
}

enum _EpisodeWhenOption { now, custom, unknown }

/// Reusable “when did you watch?” block (Now / Custom / Unknown).
class EpisodeWatchedWhenBlock extends StatefulWidget {
  const EpisodeWatchedWhenBlock({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  EpisodeWatchedWhenBlockState createState() => EpisodeWatchedWhenBlockState();
}

class EpisodeWatchedWhenBlockState extends State<EpisodeWatchedWhenBlock> {
  _EpisodeWhenOption _when = _EpisodeWhenOption.now;
  late DateTime _customLocal;

  @override
  void initState() {
    super.initState();
    _customLocal = DateTime.now();
  }

  EpisodeWatchedAtSubmit resolveSubmit() {
    final DateTime? utc = switch (_when) {
      _EpisodeWhenOption.now => DateTime.now().toUtc(),
      _EpisodeWhenOption.custom => DateTime(
        _customLocal.year,
        _customLocal.month,
        _customLocal.day,
        _customLocal.hour,
        _customLocal.minute,
      ).toUtc(),
      _EpisodeWhenOption.unknown => null,
    };
    return EpisodeWatchedAtSubmit(watchedAtUtc: utc);
  }

  Future<void> _pickDate() async {
    if (_when != _EpisodeWhenOption.custom) {
      setState(() {
        _when = _EpisodeWhenOption.custom;
        _customLocal = DateTime.now();
      });
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_customLocal.year, _customLocal.month, _customLocal.day),
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
    if (_when != _EpisodeWhenOption.custom) {
      setState(() {
        _when = _EpisodeWhenOption.custom;
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

  Widget _whenTile({required String title, required _EpisodeWhenOption value}) {
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
    final loc = MaterialLocalizations.of(context);
    final customDateLabel = loc.formatMediumDate(
      DateTime(_customLocal.year, _customLocal.month, _customLocal.day),
    );
    final customTimeLabel = TimeOfDay.fromDateTime(_customLocal).format(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle) ...[
          Text('When did you watch?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: _EpisodeDateTimeFieldChip(
                label: _when == _EpisodeWhenOption.unknown
                    ? '—'
                    : _when == _EpisodeWhenOption.now
                    ? loc.formatMediumDate(DateTime.now())
                    : customDateLabel,
                onTap: _pickDate,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _EpisodeDateTimeFieldChip(
                label: _when == _EpisodeWhenOption.unknown
                    ? '—'
                    : _when == _EpisodeWhenOption.now
                    ? TimeOfDay.now().format(context)
                    : customTimeLabel,
                onTap: _pickTime,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _whenTile(title: 'Now', value: _EpisodeWhenOption.now),
        _whenTile(title: 'Custom date', value: _EpisodeWhenOption.custom),
        _whenTile(title: 'Unknown date', value: _EpisodeWhenOption.unknown),
      ],
    );
  }
}

class _EpisodeDateTimeFieldChip extends StatelessWidget {
  const _EpisodeDateTimeFieldChip({required this.label, required this.onTap});

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

/// Bottom sheet: confirm when you watched this episode (or cancel).
Future<EpisodeWatchedAtSubmit?> showEpisodeWatchedAtSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  Color? backgroundColor,
}) {
  final theme = Theme.of(context);
  final key = GlobalKey<EpisodeWatchedWhenBlockState>();

  return showModalBottomSheet<EpisodeWatchedAtSubmit?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: backgroundColor ?? theme.colorScheme.surfaceContainerLow,
    builder: (sheetContext) {
      final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle.trim(),
                    textAlign: TextAlign.center,
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 16),
                EpisodeWatchedWhenBlock(key: key),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: () {
                    final state = key.currentState;
                    if (state == null) {
                      return;
                    }
                    Navigator.of(sheetContext).pop(state.resolveSubmit());
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
