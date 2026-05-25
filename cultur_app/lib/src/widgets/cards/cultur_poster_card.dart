import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/widgets/cards/cultur_media_card_content.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_image.dart';

/// Poster-first card: image fills width, title below (shelves, poster wall).
class CulturPosterCard extends StatelessWidget {
  const CulturPosterCard({
    required this.content,
    super.key,
    this.onTap,
    this.onLongPress,
    this.imageOverlay,
    this.posterRadius,
    this.titleStyle,
    this.titleMaxLines = 2,
  });

  final CulturMediaCardContent content;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? imageOverlay;
  final BorderRadius? posterRadius;
  final TextStyle? titleStyle;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.culturTokens;
    final radius = posterRadius ?? tokens.borderRadiusTight;

    Widget image = CulturPosterImage(
      imageUrl: content.imageUrl,
      width: double.infinity,
      height: double.infinity,
      borderRadius: radius,
      mediaType: content.mediaType,
    );

    if (imageOverlay != null) {
      image = Stack(fit: StackFit.expand, children: [image, imageOverlay!]);
    }

    return InkWell(
      borderRadius: radius,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: image),
          const SizedBox(height: 8),
          Text(
            content.title,
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: titleStyle ?? CulturCatalogTypography.gridTitle(theme),
          ),
        ],
      ),
    );
  }
}
