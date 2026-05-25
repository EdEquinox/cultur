import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_hero_carousel.dart';
import 'package:yamtrack/src/screens/widgets/movie_crew_chip.dart';
import 'package:yamtrack/src/utils/person_route_utils.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Book detail hero — same structure as [GameHeroCarousel], book metadata.
class BookHeroCarousel extends StatelessWidget {
  const BookHeroCarousel({
    super.key,
    required this.detail,
    this.overlayActions,
    this.onShareTap,
  });

  final CatalogDetail detail;
  final Widget? overlayActions;
  final VoidCallback? onShareTap;

  List<String> get _gallery {
    final url = detail.media.imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return const [];
    }
    return [url];
  }

  String get _yearLabel {
    final published = detail.factValue('First published').trim();
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(published);
    if (match != null) {
      return match.group(0)!;
    }
    final yearMeta = detail.media.metadata['firstPublishYear'];
    if (yearMeta != null) {
      return yearMeta.toString().trim();
    }
    return '';
  }

  String get _isbnLabel {
    final fromFact = detail.factValue('ISBN').trim();
    if (fromFact.isNotEmpty) {
      return fromFact;
    }
    final raw = detail.media.metadata['isbn']?.toString().trim() ?? '';
    return raw;
  }

  String get _pagesLabel {
    final pages = detail.factValue('Pages').trim();
    if (pages.isEmpty) {
      return '';
    }
    return '$pages pp.';
  }

  String get _languageLabel {
    final fromFact = detail.factValue('Language').trim();
    if (fromFact.isNotEmpty) {
      return fromFact;
    }
    return detail.media.metadata['bookLanguage']?.toString().trim() ?? '';
  }

  String get _authorsLabel {
    final names = detail.cast
        .map((person) => person.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isNotEmpty) {
      return names.take(2).join(', ');
    }
    return detail.media.subtitle?.trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final gallery = _gallery;
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.culturTokens;
    final r = tokens.radiusTight;
    final shelfBg = tokens.shelfRowBackground;
    final posterBg = tokens.shelfRowBackgroundElevated;
    final year = _yearLabel;
    final isbn = _isbnLabel;
    final pages = _pagesLabel;
    final language = _languageLabel;
    final authorsLabel = _authorsLabel;
    final authors = detail.cast;
    final authorsChips = authors.map((author) => MovieCrewChip(
      person: author,
      onTap: author.personId != null && author.personId!.isNotEmpty
          ? () => context.push(personAppRoutePath(author.personId!))
          : null,
    )).toList();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        color: scheme.surfaceContainerHigh,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                gallery.isEmpty
                    ? ColoredBox(
                        color: shelfBg,
                        child: Icon(Icons.menu_book_outlined, size: 48, color: scheme.outline),
                      )
                    : Image.network(
                        gallery.first,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (context, error, stackTrace) {
                          return ColoredBox(
                            color: shelfBg,
                            child: Icon(Icons.menu_book_outlined, size: 48, color: scheme.outline),
                          );
                        },
                      ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.scrim.withValues(alpha: 0.12),
                          scheme.scrim.withValues(alpha: 0.74),
                        ],
                      ),
                    ),
                  ),
                ),
                if (year.isNotEmpty ||
                    isbn.isNotEmpty ||
                    pages.isNotEmpty ||
                    language.isNotEmpty)
                  Positioned(
                    left: 14,
                    top: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (year.isNotEmpty || pages.isNotEmpty || language.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (year.isNotEmpty) _HeroBadge(text: year),
                              if (year.isNotEmpty && pages.isNotEmpty)
                                const SizedBox(width: 8),
                              if (pages.isNotEmpty) _HeroBadge(text: pages),
                              if ((year.isNotEmpty || pages.isNotEmpty) &&
                                  language.isNotEmpty)
                                const SizedBox(width: 8),
                              if (language.isNotEmpty) _HeroBadge(text: language),
                            ],
                          ),
                        if ((year.isNotEmpty || pages.isNotEmpty || language.isNotEmpty) &&
                            isbn.isNotEmpty)
                          const SizedBox(height: 8),
                        if (isbn.isNotEmpty) _HeroBadge(text: 'ISBN: $isbn'),
                      ],
                    ),
                  ),
                if (overlayActions != null)
                  Positioned(
                    top: 14,
                    right: 14,
                    child: overlayActions!,
                  ),
                if (onShareTap != null)
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: GameHeroOverlayPinButton(
                      icon: Icons.share_outlined,
                      tooltip: 'Copy link',
                      onPressed: onShareTap,
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(r),
                  child: SizedBox(
                    width: 84,
                    height: 126,
                    child: gallery.isEmpty
                        ? ColoredBox(
                            color: posterBg,
                            child: Icon(Icons.menu_book_outlined, color: scheme.outline),
                          )
                        : Image.network(
                            gallery.first,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return ColoredBox(
                                color: posterBg,
                                child: Icon(Icons.menu_book_outlined, color: scheme.outline),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        detail.media.title,
                        style: CulturCatalogTypography.listTitleBig(Theme.of(context)),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (authorsLabel.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        authorsChips[0],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = context.culturTokens.radiusTight;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.scrim.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(r),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: CulturCatalogTypography.gridTitle(Theme.of(context)).copyWith(
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
