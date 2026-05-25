import 'package:flutter/material.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class GenresTagsCard extends StatefulWidget {
  const GenresTagsCard({
    super.key,
    required this.genres,
    required this.keywords,
    this.onGenreTap,
    this.onKeywordTap,
  });

  final List<String> genres;
  final List<String> keywords;
  final ValueChanged<String>? onGenreTap;
  final ValueChanged<String>? onKeywordTap;

  @override
  State<GenresTagsCard> createState() => _GenresTagsCardState();
}

class _GenresTagsCardState extends State<GenresTagsCard> {
  static const _collapsedKeywordCount = 12;
  late bool _keywordsExpanded;

  @override
  void initState() {
    super.initState();
    _keywordsExpanded = widget.keywords.length <= _collapsedKeywordCount;
  }

  static String _titleCaseWord(String w) {
    if (w.isEmpty) {
      return w;
    }
    return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
  }

  static String _formatGenreLabel(String raw) {
    return raw
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map(_titleCaseWord)
        .join(' ');
  }

  static IconData _genreIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('adventure')) {
      return Icons.map_outlined;
    }
    if (n.contains('drama')) {
      return Icons.theater_comedy_outlined;
    }
    if (n.contains('science') || n.contains('sci-fi') || n.contains('sci fi')) {
      return Icons.rocket_launch_outlined;
    }
    if (n.contains('action')) {
      return Icons.flash_on_outlined;
    }
    if (n.contains('comedy')) {
      return Icons.sentiment_very_satisfied_outlined;
    }
    if (n.contains('horror')) {
      return Icons.dark_mode_outlined;
    }
    if (n.contains('thriller')) {
      return Icons.psychology_outlined;
    }
    if (n.contains('romance')) {
      return Icons.favorite_border;
    }
    if (n.contains('animation')) {
      return Icons.animation;
    }
    if (n.contains('fantasy')) {
      return Icons.auto_fix_high_outlined;
    }
    if (n.contains('documentary')) {
      return Icons.videocam_outlined;
    }
    if (n.contains('crime')) {
      return Icons.gavel;
    }
    if (n.contains('mystery')) {
      return Icons.visibility_outlined;
    }
    return Icons.movie_filter_outlined;
  }

  static String _keywordDisplay(String raw) {
    var s = raw.trim();
    if (s.startsWith('#')) {
      s = s.substring(1).trim();
    }
    return s.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visibleKeywords = _keywordsExpanded
        ? widget.keywords
        : widget.keywords.take(_collapsedKeywordCount).toList();
    final hasOverflow =
        widget.keywords.length > _collapsedKeywordCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.genres.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final genre in widget.genres)
                    Material(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: widget.onGenreTap == null
                            ? null
                            : () => widget.onGenreTap!(genre),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _genreIcon(genre),
                                size: 18,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatGenreLabel(genre),
                                style: CulturCatalogTypography.gridTitle(theme),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            if (widget.keywords.isNotEmpty) ...[
              if (widget.genres.isNotEmpty) const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kw in visibleKeywords)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: widget.onKeywordTap == null
                            ? null
                            : () => widget.onKeywordTap!(kw),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Text.rich(
                            TextSpan(
                              style: CulturCatalogTypography.gridTitle(theme),
                              children: [
                                TextSpan(
                                  text: '# ',
                                  style: CulturCatalogTypography.gridSubtitle(
                                    theme,
                                    scheme,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),
                                TextSpan(
                                  text: _keywordDisplay(kw),
                                  style: CulturCatalogTypography.gridTitle(theme)
                                      .copyWith(fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (hasOverflow) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _keywordsExpanded = !_keywordsExpanded;
                    });
                  },
                  icon: Icon(
                    _keywordsExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  label: Text(
                    _keywordsExpanded ? 'Show less' : 'Show all tags',
                    style: CulturCatalogTypography.linkAction(theme, scheme),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
