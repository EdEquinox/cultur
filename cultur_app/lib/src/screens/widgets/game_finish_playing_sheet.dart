import 'package:flutter/material.dart';

import 'rating_stars_row.dart';

enum GamePlayingOutcome { played, dropped, paused }

enum _ActionWhenOption { now, custom }

class GameFinishPlayingSheetResult {
  const GameFinishPlayingSheetResult({
    required this.outcome,
    this.score,
    this.actionAtUtc,
  });

  final GamePlayingOutcome outcome;
  final double? score;
  final DateTime? actionAtUtc;
}

/// Shown when stopping an in-progress game: pick played vs dropped and optional rating.
class GameFinishPlayingSheet extends StatefulWidget {
  const GameFinishPlayingSheet({
    super.key,
    required this.gameTitle,
    this.initialScore,
  });

  final String gameTitle;
  final double? initialScore;

  @override
  State<GameFinishPlayingSheet> createState() => _GameFinishPlayingSheetState();
}

class _GameFinishPlayingSheetState extends State<GameFinishPlayingSheet> {
  GamePlayingOutcome? _outcome;
  late int _stars;
  _ActionWhenOption _when = _ActionWhenOption.now;
  late DateTime _customLocal;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialScore;
    _stars = initial != null && initial > 0 ? initial.round().clamp(0, 10) : 0;
    _customLocal = DateTime.now();
  }

  Future<void> _pickDate() async {
    if (_when != _ActionWhenOption.custom) {
      setState(() {
        _when = _ActionWhenOption.custom;
        _customLocal = DateTime.now();
      });
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_customLocal.year, _customLocal.month, _customLocal.day),
      firstDate: DateTime(1970),
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

  DateTime? get _actionAtUtc {
    if (_outcome == GamePlayingOutcome.paused) {
      return null;
    }
    return switch (_when) {
      _ActionWhenOption.now => DateTime.now().toUtc(),
      _ActionWhenOption.custom => DateTime(
        _customLocal.year,
        _customLocal.month,
        _customLocal.day,
        _customLocal.hour,
        _customLocal.minute,
      ).toUtc(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Playing',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            if (widget.gameTitle.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.gameTitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'What happened?',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            _OutcomeTile(
              selected: _outcome == GamePlayingOutcome.played,
              icon: Icons.check_circle_outline,
              selectedIcon: Icons.check_circle,
              label: 'Finished the game',
              subtitle: 'Moves to Played',
              onTap: () => setState(() => _outcome = GamePlayingOutcome.played),
            ),
            const SizedBox(height: 8),
            _OutcomeTile(
              selected: _outcome == GamePlayingOutcome.dropped,
              icon: Icons.flag_outlined,
              selectedIcon: Icons.flag,
              label: 'Dropped it',
              subtitle: 'Moves to Dropped',
              onTap: () => setState(() => _outcome = GamePlayingOutcome.dropped),
            ),
            const SizedBox(height: 8),
            _OutcomeTile(
              selected: _outcome == GamePlayingOutcome.paused,
              icon: Icons.pause_circle_outline,
              selectedIcon: Icons.pause_circle,
              label: 'Pause for now',
              subtitle: 'Back to Later',
              onTap: () => setState(() => _outcome = GamePlayingOutcome.paused),
            ),
            const SizedBox(height: 24),
            if (_outcome != GamePlayingOutcome.paused) ...[
              Text(
                'When?',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Today'),
                leading: Icon(
                  _when == _ActionWhenOption.now
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: () => setState(() => _when = _ActionWhenOption.now),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _when == _ActionWhenOption.custom
                      ? MaterialLocalizations.of(context).formatMediumDate(
                          DateTime(_customLocal.year, _customLocal.month, _customLocal.day),
                        )
                      : 'Pick a date',
                ),
                leading: Icon(
                  _when == _ActionWhenOption.custom
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: _pickDate,
              ),
              const SizedBox(height: 16),
              Text(
                'Your rating (optional)',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              RatingStarsRow(
                selectedCount: _stars,
                onChanged: (value) => setState(() => _stars = value),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _outcome == null
                        ? null
                        : () {
                            Navigator.of(context).pop(
                              GameFinishPlayingSheetResult(
                                outcome: _outcome!,
                                score: _stars > 0 ? _stars.toDouble() : null,
                                actionAtUtc: _actionAtUtc,
                              ),
                            );
                          },
                    child: const Text('Save'),
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

class _OutcomeTile extends StatelessWidget {
  const _OutcomeTile({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? selectedIcon : icon,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer.withValues(alpha: 0.85)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check, color: scheme.onPrimaryContainer, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
