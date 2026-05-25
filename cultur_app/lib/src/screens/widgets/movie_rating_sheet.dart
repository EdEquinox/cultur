import 'package:flutter/material.dart';

import 'package:yamtrack/src/models/rating_sheet_result.dart';
import 'rating_stars_row.dart';

class MovieRatingSheet extends StatelessWidget {
  const MovieRatingSheet({
    super.key,
    required this.selectedStars,
    required this.onStarsChanged,
    required this.onCancel,
    required this.onSave,
    this.hasExistingRating = false,
    this.title = 'Rate this movie',
    this.prompt = 'Rate movie?',
  });

  /// 0–10, same semantics as the watched sheet star row.
  final int selectedStars;
  final ValueChanged<int> onStarsChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final bool hasExistingRating;
  final String title;
  final String prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceContainerHigh,
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              prompt,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            RatingStarsRow(
              selectedCount: selectedStars,
              onChanged: onStarsChanged,
            ),
            if (hasExistingRating) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(const RatingSheetRemoved()),
                icon: Icon(Icons.delete_outline, color: scheme.error),
                label: Text(
                  'Remove rating',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: selectedStars > 0 ? onSave : null,
                    child: Text(hasExistingRating && selectedStars == 0 ? 'Save' : 'Save rating'),
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
