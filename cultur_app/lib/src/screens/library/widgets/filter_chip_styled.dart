import 'package:flutter/material.dart';

class FilterChipStyled extends StatelessWidget {
  const FilterChipStyled({super.key, 
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 20,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
