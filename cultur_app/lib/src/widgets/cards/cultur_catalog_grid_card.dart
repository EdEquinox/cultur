import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_metrics.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/widgets/cards/cultur_media_card_content.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_image.dart';

/// Compact poster grid cell used across movies, TV, games catalog search and Collected.
class CulturCatalogGridCard extends StatelessWidget {
  const CulturCatalogGridCard({
    required this.item,
    super.key,
    this.onTap,
    this.onLongPress,
    this.imageOverlay,
    this.synopsisLine,
    this.footerLines = const [],
  });

  final CatalogItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? imageOverlay;

  /// Optional synopsis (e.g. book first sentence) below the subtitle line.
  final String? synopsisLine;

  /// Extra lines below title/subtitle (e.g. borrower name on lent cards).
  final List<Widget> footerLines;

  static const double posterAspectRatio = CulturCatalogGridMetrics.posterAspectRatio;
  static const double gridChildAspectRatio = CulturCatalogGridMetrics.gridChildAspectRatio;

  static double totalHeightForWidth(double width) =>
      CulturCatalogGridMetrics.totalHeightForWidth(width);

  CulturMediaCardContent get _content {
    final type = item.mediaType.trim().toLowerCase();
    if (type == 'game') {
      return CulturMediaCardContent.fromGameCatalog(item);
    }
    return CulturMediaCardContent.fromCatalog(item);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.culturTokens;
    final content = _content;
    final secondary = catalogItemGridSecondaryLine(item);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: posterAspectRatio,
          child: ClipRRect(
            borderRadius: tokens.borderRadiusTight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  child: CulturPosterImage(
                    imageUrl: content.imageUrl,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: tokens.borderRadiusTight,
                    mediaType: content.mediaType,
                  ),
                ),
                ?imageOverlay,
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: tokens.borderRadiusTight,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                content.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CulturCatalogTypography.gridTitle(theme),
              ),
              if (secondary.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CulturCatalogTypography.gridSubtitle(theme, scheme),
                ),
              ],
              if (synopsisLine != null && synopsisLine!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  synopsisLine!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CulturCatalogTypography.gridSubtitle(theme, scheme).copyWith(
                    fontSize: 10,
                    height: 1.2,
                  ),
                ),
              ],
              ...footerLines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: line,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
