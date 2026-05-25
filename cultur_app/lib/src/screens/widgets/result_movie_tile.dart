import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/widgets/movie_poster_thumb.dart';
import 'package:yamtrack/src/screens/widgets/movie_quick_actions_bar.dart';

class ResultMovieTile extends StatelessWidget {
  const ResultMovieTile({super.key, 
    required this.item,
    required this.tracking,
    required this.isSaving,
    this.onTap,
    this.onWatchlistTap,
    this.onWatchedTap,
  });

  final CatalogItem item;
  final TrackingItem? tracking;
  final bool isSaving;
  final VoidCallback? onTap;
  final VoidCallback? onWatchlistTap;
  final VoidCallback? onWatchedTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MoviePosterThumb(
                imageUrl: item.imageUrl,
                width: 72,
                height: 108,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(width: 12),
              MovieQuickActionsBar(
                tracking: tracking,
                isSaving: isSaving,
                compact: true,
                iconOnly: true,
                vertical: true,
                onWatchlistTap: onWatchlistTap,
                onWatchedTap: onWatchedTap,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (item.description != null && item.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.description!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
