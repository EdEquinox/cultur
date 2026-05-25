import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_list_row.dart';

class CustomListMovieTile extends StatelessWidget {
  const CustomListMovieTile({super.key, 
    required this.item,
    this.onTap,
    this.onLongPress,
    this.showRemoveButton = false,
    this.onRemove,
    this.mediaTypeOverride,
  });

  final CatalogItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showRemoveButton;
  final VoidCallback? onRemove;
  final String? mediaTypeOverride;

  @override
  Widget build(BuildContext context) {
    return CulturCatalogListRow(
      item: item,
      metaParts: mediaTypeOverride == null
          ? null
          : catalogRowMetaPartsForCatalogList(
              item,
              mediaTypeOverride: mediaTypeOverride,
            ),
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: showRemoveButton && onRemove != null
          ? IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Remove from list',
              onPressed: onRemove,
              iconSize: 18,
            )
          : null,
    );
  }
}
