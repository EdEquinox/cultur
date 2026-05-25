import 'package:flutter/material.dart';
import 'package:yamtrack/src/screens/library/widgets/library_filter_option.dart';

/// Opens a compact dropdown menu anchored below [anchorKey] to pick a filter.
Future<void> showLibraryFilterMenu(
  BuildContext context, {
  required GlobalKey anchorKey,
  required List<LibraryFilterOption> options,
  VoidCallback? onClearAll,
}) async {
  if (options.isEmpty) {
    return;
  }

  final anchorContext = anchorKey.currentContext;
  final button = anchorContext?.findRenderObject() as RenderBox?;
  if (button == null || !button.hasSize) {
    return;
  }

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final offset = button.localToGlobal(Offset.zero, ancestor: overlay);
  final position = RelativeRect.fromLTRB(
    offset.dx,
    offset.dy + button.size.height + 4,
    offset.dx + button.size.width,
    overlay.size.height - offset.dy - button.size.height,
  );

  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final activeCount = libraryActiveFilterCount(options);

  await showMenu<void>(
    context: context,
    position: position,
    elevation: 6,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    color: scheme.surfaceContainerLow,
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
    items: [
      PopupMenuItem<void>(
        enabled: false,
        height: 36,
        child: Row(
          children: [
            Text(
              'Filters',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (activeCount > 0)
              Text(
                '$activeCount active',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
      for (final option in options)
        PopupMenuItem<void>(
          height: 40,
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              option.onPick(context);
            });
          },
          child: Row(
            children: [
              Icon(
                option.isActive ? Icons.filter_alt : Icons.filter_alt_outlined,
                size: 18,
                color: option.isActive ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                ),
              ),
              if (option.isActive)
                Icon(Icons.check, size: 18, color: scheme.primary),
            ],
          ),
        ),
      if (activeCount > 0 && onClearAll != null) ...[
        const PopupMenuDivider(height: 8),
        PopupMenuItem<void>(
          height: 40,
          onTap: () {
            Navigator.pop(context);
            onClearAll();
          },
          child: Row(
            children: [
              Icon(Icons.clear_all, size: 18, color: scheme.error),
              const SizedBox(width: 10),
              Text(
                'Clear all filters',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}
