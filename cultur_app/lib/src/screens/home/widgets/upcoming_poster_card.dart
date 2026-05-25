import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_image.dart';

/// Small poster chip in the upcoming home timeline strip.
class UpcomingPosterCard extends StatelessWidget {
  const UpcomingPosterCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  static const double width = 92;
  static const double height = 138;

  final CatalogItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.culturTokens;
    final borderColor = isSelected ? theme.colorScheme.primary : Colors.transparent;

    return InkWell(
      borderRadius: tokens.borderRadiusTight,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: tokens.borderRadiusTight,
          border: Border.all(color: borderColor, width: 2),
        ),
        child: ClipRRect(
          borderRadius: tokens.borderRadiusTight,
          child: CulturPosterImage(
            imageUrl: item.imageUrl,
            width: width,
            height: height,
            borderRadius: tokens.borderRadiusTight,
            mediaType: item.mediaType,
          ),
        ),
      ),
    );
  }
}
