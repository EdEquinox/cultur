import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Compact outlined crew chip: small square avatar + name.
class MovieCrewChip extends StatelessWidget {
  const MovieCrewChip({
    super.key,
    required this.person,
    this.onTap,
    this.expand = false,
  });

  final MovieDetailPerson person;
  final VoidCallback? onTap;

  /// When true, stretches to the parent width (e.g. full-width list rows).
  final bool expand;

  static const double avatarSize = 20;
  static const double minHeight = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.culturTokens;
    final r = tokens.radiusTight + 2;
    final shelfBg = tokens.shelfRowBackground;
    final hasPhoto = person.imageUrl != null && person.imageUrl!.isNotEmpty;

    final name = Text(
      person.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: CulturCatalogTypography.gridTitle(theme),
    );

    final rowChildren = <Widget>[
      if (hasPhoto) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(r - 2),
          child: SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: Image.network(
              person.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return ColoredBox(
                  color: tokens.shelfRowBackgroundElevated,
                  child: Icon(
                    Icons.person_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
      if (expand) Expanded(child: name) else name,
    ];

    return Material(
      color: shelfBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 4,
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: rowChildren,
            ),
          ),
        ),
      ),
    );
  }
}
