import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/widgets/cards/cultur_media_card_content.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_image.dart';

/// Visual style for grid tiles (catalog browse vs library).
enum CulturGridTileStyle {
  /// Filled surface container; image clipped with tight radius (library).
  flat,

  /// Elevated panel; image with rounded top (catalog search grid).
  elevated,
}

/// Grid cell: poster on top, title (and optional subtitle) below.
class CulturGridTile extends StatelessWidget {
  const CulturGridTile({
    required this.content,
    super.key,
    this.style = CulturGridTileStyle.flat,
    this.compact = false,
    this.onTap,
    this.onLongPress,
    this.imageOverlay,
    this.showSubtitle = true,
  });

  final CulturMediaCardContent content;
  final CulturGridTileStyle style;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? imageOverlay;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.culturTokens;
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isElevated = style == CulturGridTileStyle.elevated;

    final imageRadius = isElevated
        ? BorderRadius.vertical(
            top: Radius.circular(compact ? 12 : 20),
          )
        : tokens.borderRadiusTight;

    Widget image = CulturPosterImage(
      imageUrl: content.imageUrl,
      width: double.infinity,
      height: double.infinity,
      borderRadius: imageRadius,
      mediaType: content.mediaType,
    );

    if (imageOverlay != null) {
      image = Stack(
        fit: StackFit.expand,
        children: [image, imageOverlay!],
      );
    }

    final ink = InkWell(
      borderRadius: tokens.borderRadiusTight,
      onTap: onTap,
      onLongPress: onLongPress,
      child: isElevated
          ? Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: tokens.borderRadiusTight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ClipRRect(borderRadius: imageRadius, child: image)),
                  _TextBlock(
                    content: content,
                    theme: theme,
                    showSubtitle: showSubtitle,
                    compact: compact,
                    padding: compact
                        ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
                        : const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  ),
                ],
              ),
            )
          : Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: tokens.borderRadiusTight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: tokens.borderRadiusTight,
                      child: image,
                    ),
                  ),
                  _TextBlock(
                    content: content,
                    theme: theme,
                    showSubtitle: false,
                    compact: compact,
                    padding: compact
                        ? const EdgeInsets.all(8)
                        : const EdgeInsets.all(12),
                    titleStyle: CulturCatalogTypography.listTitle(theme),
                  ),
                ],
              ),
            ),
    );

    return ink;
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({
    required this.content,
    required this.theme,
    required this.showSubtitle,
    required this.compact,
    required this.padding,
    this.titleStyle,
  });

  final CulturMediaCardContent content;
  final ThemeData theme;
  final bool showSubtitle;
  final bool compact;
  final EdgeInsetsGeometry padding;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final subtitle = content.subtitle;
    final titleTextStyle = titleStyle ??
        (compact
            ? CulturCatalogTypography.gridTitle(theme)
            : CulturCatalogTypography.listTitle(theme));
    final subtitleStyle = compact
        ? CulturCatalogTypography.gridSubtitle(theme, scheme)
        : CulturCatalogTypography.listMeta(theme, scheme);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            content.title,
            maxLines: compact ? 2 : 2,
            overflow: TextOverflow.ellipsis,
            style: titleTextStyle,
          ),
          if (showSubtitle && subtitle != null && subtitle.isNotEmpty) ...[
            SizedBox(height: compact ? 2 : 4),
            Text(
              subtitle,
              maxLines: compact ? 2 : 2,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
            ),
          ],
        ],
      ),
    );
  }
}
