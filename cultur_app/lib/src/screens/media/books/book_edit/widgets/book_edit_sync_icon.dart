import 'package:flutter/material.dart';

/// Small sync control shown beside editable book fields (mockup).
class BookEditSyncIcon extends StatelessWidget {
  const BookEditSyncIcon({
    required this.onPressed,
    this.size = 22,
    super.key,
  });

  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Icons.sync,
            size: size,
            color: scheme.primary.withValues(alpha: 0.95),
          ),
        ),
      ),
    );
  }
}
