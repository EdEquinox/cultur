import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Vertical cast card: portrait, name, character tag.
class MoviePersonCard extends StatelessWidget {
  const MoviePersonCard({
    super.key,
    required this.person,
    this.onTap,
    this.width = cardWidth,
  });

  final MovieDetailPerson person;
  final VoidCallback? onTap;

  /// When null, the card fills the parent width (e.g. grid cells).
  final double? width;

  static const double cardWidth = 124;

  /// Height for horizontal cast rows (1-line name + 1-line role chip).
  static const double shelfExtent = 192;

  /// Grid row height for full cast pages.
  static const double gridMainAxisExtent = 186;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.culturTokens;
    final r = tokens.radiusTight;
    final shelfBg = tokens.shelfRowBackground;
    final role = person.role?.trim() ?? '';
    final hasRole = role.isNotEmpty;

    final card = Material(
        color: shelfBg,
        borderRadius: BorderRadius.circular(r),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(r),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: person.imageUrl == null || person.imageUrl!.isEmpty
                        ? ColoredBox(
                            color: tokens.shelfRowBackgroundElevated,
                            child: Icon(
                              Icons.person_outline,
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        : Image.network(
                            person.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return ColoredBox(
                                color: tokens.shelfRowBackgroundElevated,
                                child: Icon(
                                  Icons.person_outline,
                                  color: scheme.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CulturCatalogTypography.listTitle(theme),
                ),
                if (hasRole) ...[
                  const SizedBox(height: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.shelfRowBackgroundElevated,
                      borderRadius: BorderRadius.circular(r),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CulturCatalogTypography.listMeta(theme, scheme),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    );

    if (width != null) {
      return SizedBox(width: width, child: card);
    }
    return card;
  }
}
