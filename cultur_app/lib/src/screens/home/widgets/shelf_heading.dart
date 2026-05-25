import 'package:flutter/material.dart';

class ShelfHeading extends StatelessWidget {
  const ShelfHeading({
    super.key,
    required this.title,
    required this.icon,
    this.onSeeAll,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onSeeAll;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (trailing != null) ...[
          trailing!,
          const SizedBox(width: 4),
        ],
        if (onSeeAll != null)
          IconButton(
            onPressed: onSeeAll,
            tooltip: 'See all',
            icon: Icon(Icons.chevron_right_rounded, color: muted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
      ],
    );
  }
}
