import 'package:flutter/material.dart';

/// Ten-star row (1–10), same interaction as [MarkWatchedSheet].
class RatingStarsRow extends StatelessWidget {
  const RatingStarsRow({
    super.key,
    required this.selectedCount,
    required this.onChanged,
  });

  /// Number of filled stars (0 = none). Tapping the same star again clears to 0.
  final int selectedCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 10; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: InkWell(
                    onTap: () => onChanged(selectedCount == i ? 0 : i),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        i <= selectedCount ? Icons.star : Icons.star_border,
                        size: 26,
                        color: i <= selectedCount
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
