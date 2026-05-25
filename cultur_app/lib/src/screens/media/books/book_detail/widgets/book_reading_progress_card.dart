import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/utils/book_progress_utils.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class BookReadingProgressCard extends StatelessWidget {
  const BookReadingProgressCard({
    super.key,
    required this.detail,
    required this.tracking,
    required this.isSaving,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final CatalogDetail detail;
  final TrackingItem? tracking;
  final bool isSaving;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentPage = bookCurrentPage(tracking);
    final totalPages = bookPageCount(detail.media);
    final showControls = trackingIsDoing(tracking) || currentPage > 0;
    final status = tracking != null
        ? bookReadingProgressLabel(tracking: tracking!)
        : 'Not started';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reading progress', style: CulturCatalogTypography.sectionHeading(theme)),
            const SizedBox(height: 8),
            Text(status, style: CulturCatalogTypography.listMeta(theme, scheme)),
            if (showControls) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: isSaving || currentPage <= 0 ? null : onPreviousPage,
                    icon: const Icon(Icons.remove),
                  ),
                  Expanded(
                    child: Text(
                      'Page $currentPage${totalPages != null ? ' / $totalPages' : ''}',
                      textAlign: TextAlign.center,
                      style: CulturCatalogTypography.listTitle(theme),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: isSaving ? null : onNextPage,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                'Mark as Reading to track your page.',
                style: CulturCatalogTypography.listMeta(theme, scheme),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
