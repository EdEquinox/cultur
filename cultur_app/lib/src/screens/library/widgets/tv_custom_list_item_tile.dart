import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/screens/library/widgets/library_watched_style_catalog_row.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

class TvCustomListItemTile extends StatelessWidget {
  const TvCustomListItemTile({super.key, 
    required this.item,
    this.onTap,
    this.showRemoveButton = false,
    this.onRemove,
  });

  final TvCustomListItem item;
  final VoidCallback? onTap;
  final bool showRemoveButton;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;
    return LibraryWatchedStyleCatalogRow(
      title: item.show.title,
      imageUrl: item.show.imageUrl,
      metaParts: catalogRowMetaPartsForTvListItem(item),
      accentColor: accent,
      onTap: onTap,
      trailing: showRemoveButton && onRemove != null
          ? IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Remove from list',
              onPressed: onRemove,
              iconSize: 18,
            )
          : onTap != null
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
    );
  }
}
