import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/screens/media/books/book_edit/widgets/book_edit_sync_icon.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Book edit hero — mirrors [BookHeroCarousel] with sync + tap-to-edit hooks.
class BookEditHero extends StatelessWidget {
  const BookEditHero({
    required this.imageUrl,
    required this.title,
    required this.authorsLabel,
    required this.year,
    required this.pages,
    required this.language,
    required this.isbn,
    required this.onTitleTap,
    required this.onTitleSync,
    required this.onAuthorsTap,
    required this.onAuthorsSync,
    required this.onYearTap,
    required this.onYearSync,
    required this.onPagesTap,
    required this.onPagesSync,
    required this.onLanguageTap,
    required this.onLanguageSync,
    required this.onIsbnTap,
    required this.onIsbnSync,
    this.titleHighlighted = false,
    this.authorsHighlighted = false,
    super.key,
  });

  final String? imageUrl;
  final String title;
  final String authorsLabel;
  final String year;
  final String pages;
  final String language;
  final String isbn;
  final VoidCallback onTitleTap;
  final VoidCallback onTitleSync;
  final VoidCallback onAuthorsTap;
  final VoidCallback onAuthorsSync;
  final VoidCallback onYearTap;
  final VoidCallback onYearSync;
  final VoidCallback onPagesTap;
  final VoidCallback onPagesSync;
  final VoidCallback onLanguageTap;
  final VoidCallback onLanguageSync;
  final VoidCallback onIsbnTap;
  final VoidCallback onIsbnSync;
  final bool titleHighlighted;
  final bool authorsHighlighted;

  List<String> get _gallery {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return const [];
    }
    return [url];
  }

  @override
  Widget build(BuildContext context) {
    final gallery = _gallery;
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.culturTokens;
    final r = tokens.radiusTight;
    final shelfBg = tokens.shelfRowBackground;
    final posterBg = tokens.shelfRowBackgroundElevated;

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
                              if (year.isNotEmpty)
                                _EditableHeroBadge(
                                  text: year,
                                  highlighted: false,
                                  onTap: onYearTap,
                                  onSync: onYearSync,
                                ),
                              if (year.isNotEmpty && pages.isNotEmpty) const SizedBox(width: 8),
                              if (pages.isNotEmpty)
                                _EditableHeroBadge(
                                  text: pages,
                                  highlighted: false,
                                  onTap: onPagesTap,
                                  onSync: onPagesSync,
                                ),
                              if ((year.isNotEmpty || pages.isNotEmpty) && language.isNotEmpty)
                                const SizedBox(width: 8),
                              if (language.isNotEmpty)
                                _EditableHeroBadge(
                                  text: language,
                                  highlighted: false,
                                  onTap: onLanguageTap,
                                  onSync: onLanguageSync,
                                ),
                            ],
                          ),
                        if ((year.isNotEmpty || pages.isNotEmpty || language.isNotEmpty) &&
                            isbn.isNotEmpty)
                          const SizedBox(height: 8),
                        if (isbn.isNotEmpty)
                          _EditableHeroBadge(
                            text: 'ISBN: $isbn',
                            highlighted: false,
                            onTap: onIsbnTap,
                            onSync: onIsbnSync,
                          ),
                      ],
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
                      _EditableHeroTitle(
                        title: title.isEmpty ? 'Untitled' : title,
                        highlighted: titleHighlighted,
                        onTap: onTitleTap,
                        onSync: onTitleSync,
                      ),
                      if (authorsLabel.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _EditableHeroAuthorChip(
                          label: authorsLabel,
                          highlighted: authorsHighlighted,
                          onTap: onAuthorsTap,
                          onSync: onAuthorsSync,
                        ),
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

class _EditableHeroBadge extends StatelessWidget {
  const _EditableHeroBadge({
    required this.text,
    required this.highlighted,
    required this.onTap,
    required this.onSync,
  });

  final String text;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = context.culturTokens.radiusTight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        BookEditSyncIcon(onPressed: onSync, size: 18),
        const SizedBox(height: 2),
        Material(
          color: highlighted
              ? scheme.primaryContainer.withValues(alpha: 0.55)
              : scheme.scrim.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r),
            side: highlighted
                ? BorderSide(color: scheme.primary.withValues(alpha: 0.8))
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(r),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                text,
                style: CulturCatalogTypography.gridTitle(Theme.of(context)).copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditableHeroTitle extends StatelessWidget {
  const _EditableHeroTitle({
    required this.title,
    required this.highlighted,
    required this.onTap,
    required this.onSync,
  });

  final String title;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: BookEditSyncIcon(onPressed: onSync),
        ),
        Material(
          color: highlighted
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                title,
                style: CulturCatalogTypography.listTitleBig(Theme.of(context)),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditableHeroAuthorChip extends StatelessWidget {
  const _EditableHeroAuthorChip({
    required this.label,
    required this.highlighted,
    required this.onTap,
    required this.onSync,
  });

  final String label;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.culturTokens;
    final r = tokens.radiusTight + 2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookEditSyncIcon(onPressed: onSync, size: 18),
              const SizedBox(height: 2),
              Material(
                color: highlighted
                    ? scheme.primaryContainer.withValues(alpha: 0.45)
                    : tokens.shelfRowBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(r),
                  side: BorderSide(
                    color: highlighted
                        ? scheme.primary.withValues(alpha: 0.75)
                        : scheme.outline.withValues(alpha: 0.45),
                  ),
                ),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CulturCatalogTypography.gridTitle(Theme.of(context)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
