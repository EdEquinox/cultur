import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/screens/library/widgets/library_watched_style_catalog_row.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

/// List row for catalog search and personal lists (movies, TV, games).
class CulturCatalogListRow extends StatelessWidget {
  const CulturCatalogListRow({
    required this.item,
    super.key,
    this.onTap,
    this.onLongPress,
    this.metaParts,
    this.trailing,
    this.score,
    this.accentColor,
  });

  final CatalogItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final List<String>? metaParts;
  final Widget? trailing;
  final double? score;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.tertiary;
    final parts = metaParts ?? catalogRowMetaPartsForCatalogList(item);

    return LibraryWatchedStyleCatalogRow(
      title: item.title,
      imageUrl: item.imageUrl,
      metaParts: parts,
      accentColor: accent,
      score: score,
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: trailing ??
          (onTap != null
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : null),
    );
  }
}
