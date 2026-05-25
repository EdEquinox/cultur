import 'package:flutter/material.dart';

class MovieQuickActionButton extends StatelessWidget {
  const MovieQuickActionButton({super.key, 
    required this.label,
    required this.icon,
    required this.active,
    required this.compact,
    required this.iconOnly,
    required this.isLoading,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool compact;
  final bool iconOnly;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final buttonIcon = isLoading
        ? const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: compact || iconOnly ? 16 : 18);

    if (iconOnly) {
      return IconButton.filledTonal(
        tooltip: label,
        onPressed: onPressed,
        icon: buttonIcon,
        style: IconButton.styleFrom(
          backgroundColor: active
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          minimumSize: const Size(34, 34),
          padding: const EdgeInsets.all(8),
        ),
      );
    }

    final style = active
        ? FilledButton.styleFrom(
            visualDensity: compact ? VisualDensity.compact : null,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 8 : 10,
            ),
          )
        : OutlinedButton.styleFrom(
            visualDensity: compact ? VisualDensity.compact : null,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 8 : 10,
            ),
          );

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        buttonIcon,
        const SizedBox(width: 6),
        Text(label),
      ],
    );

    if (active) {
      return FilledButton(
        onPressed: onPressed,
        style: style,
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}
