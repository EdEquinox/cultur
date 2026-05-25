import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/widgets/cards/cultur_card_shell.dart';
import 'package:yamtrack/src/widgets/cards/cultur_media_card_content.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_image.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_size.dart';

/// List row for catalog search, library tracking, and similar dense lists.
enum CulturListRowDensity {
  /// Poster + title block + optional description.
  detailed,

  /// Poster + inline actions + title + chevron.
  compact,
}

/// Where [CulturListRowCard.actions] sit in [CulturListRowDensity.detailed] rows.
enum CulturListRowActionsPlacement {
  /// Poster | actions | body (catalog browse).
  leading,

  /// Poster | body with actions below text (library).
  footer,
}

class CulturListRowCard extends StatelessWidget {
  const CulturListRowCard({
    required this.content,
    super.key,
    this.density = CulturListRowDensity.detailed,
    this.onTap,
    this.onLongPress,
    this.actions,
    this.metaLine,
    this.descriptionMaxLines,
    this.posterRadius,
    this.showChevron,
    this.actionsPlacement = CulturListRowActionsPlacement.footer,
    this.trailing,
  });

  final CulturMediaCardContent content;
  final CulturListRowDensity density;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? actions;
  final String? metaLine;
  final int? descriptionMaxLines;
  final BorderRadius? posterRadius;
  final bool? showChevron;
  final CulturListRowActionsPlacement actionsPlacement;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isCompact = density == CulturListRowDensity.compact;
    final preset =
        isCompact ? CulturPosterSizePreset.md : CulturPosterSizePreset.lg;
    final tokens = context.culturTokens;
    final radius = posterRadius ??
        (isCompact ? tokens.borderRadiusTight : BorderRadius.circular(18));

    return CulturCardShell(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CulturPosterImage(
            imageUrl: content.imageUrl,
            preset: preset,
            borderRadius: radius,
            mediaType: content.mediaType,
          ),
          const SizedBox(width: 12),
          if (_actionsLeading) ...[
            actions!,
            const SizedBox(width: 12),
          ],
          Expanded(child: _Body(card: this)),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing!,
          ] else if (isCompact && (showChevron ?? true)) ...[
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right),
          ],
        ],
      ),
    );
  }

  bool get _actionsLeading =>
      actions != null &&
      (density == CulturListRowDensity.compact ||
          (density == CulturListRowDensity.detailed &&
              actionsPlacement == CulturListRowActionsPlacement.leading));
}

class _Body extends StatelessWidget {
  const _Body({required this.card});

  final CulturListRowCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = card.content;
    final isCompact = card.density == CulturListRowDensity.compact;
    final titleStyle = CulturCatalogTypography.listTitle(theme);
    final subtitle = content.subtitle;
    final description = content.description;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          content.title,
          maxLines: isCompact ? 1 : null,
          overflow: isCompact ? TextOverflow.ellipsis : null,
          style: titleStyle,
        ),
        if (!isCompact && subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: CulturCatalogTypography.listMeta(theme, scheme)),
        ],
        if (!isCompact &&
            description != null &&
            description.isNotEmpty &&
            card.descriptionMaxLines != null) ...[
          const SizedBox(height: 8),
          Text(
            description,
            maxLines: card.descriptionMaxLines,
            overflow: TextOverflow.ellipsis,
            style: CulturCatalogTypography.bodyText(theme, scheme),
          ),
        ],
        if (isCompact && subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: isCompact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: CulturCatalogTypography.listMeta(theme, scheme),
          ),
        ],
        if (card.metaLine != null && card.metaLine!.isNotEmpty) ...[
          SizedBox(height: isCompact ? 4 : 8),
          Text(
            card.metaLine!,
            maxLines: isCompact ? 2 : null,
            overflow: isCompact ? TextOverflow.ellipsis : null,
            style: CulturCatalogTypography.listMeta(theme, scheme),
          ),
        ],
        if (!isCompact &&
            card.actions != null &&
            card.actionsPlacement == CulturListRowActionsPlacement.footer) ...[
          const SizedBox(height: 4),
          card.actions!,
        ],
      ],
    );
  }
}
