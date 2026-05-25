import 'package:flutter/material.dart';

class WatchedStarRatingBadge extends StatelessWidget {
  const WatchedStarRatingBadge({super.key, required this.score, required this.iconSize});

  final double score;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rounded = score.round().clamp(1, 10);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: iconSize, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            '$rounded',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
