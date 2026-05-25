import 'package:flutter/material.dart';

class LibraryQuickIconButton extends StatelessWidget {
  const LibraryQuickIconButton({super.key, 
    required this.icon,
    required this.active,
    required this.compact,
    required this.isLoading,
    this.onTap,
  });

  final IconData icon;
  final bool active;
  final bool compact;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: isLoading ? null : onTap,
      icon: isLoading
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: compact ? 16 : 18),
      style: IconButton.styleFrom(
        minimumSize: Size(compact ? 32 : 36, compact ? 32 : 36),
        padding: EdgeInsets.all(compact ? 7 : 8),
        backgroundColor: active
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}
