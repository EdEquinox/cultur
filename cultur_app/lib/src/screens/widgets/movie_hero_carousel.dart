import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/movie/movie_catalog_detail.dart';

import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

import 'detail_director_card.dart';
class MovieHeroCarousel extends StatefulWidget {
  const MovieHeroCarousel({
    super.key,
    required this.detail,
    this.isTv = false,
    this.overlayActions,
    this.onShareTap,
  });

  final MovieCatalogDetail detail;
  final bool isTv;

  /// Shown below the slideshow dots (top-right), e.g. priority / cinema pins.
  final Widget? overlayActions;

  /// Copy-link action on the bottom-right of the backdrop.
  final VoidCallback? onShareTap;

  @override
  State<MovieHeroCarousel> createState() => _MovieHeroCarouselState();
}

class _MovieHeroCarouselState extends State<MovieHeroCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _pageIndex = 0;

  List<String> get _gallery {
    final urls = <String>[
      ...widget.detail.galleryUrls,
      if (widget.detail.backdropUrl != null && widget.detail.backdropUrl!.isNotEmpty)
        widget.detail.backdropUrl!,
      if (widget.detail.media.imageUrl != null && widget.detail.media.imageUrl!.isNotEmpty)
        widget.detail.media.imageUrl!,
    ];
    return urls.toSet().toList();
  }

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    if (_gallery.length < 2) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      final nextPage = (_pageIndex + 1) % _gallery.length;
      _controller.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
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
                        child: Icon(Icons.movie_outlined, size: 48, color: scheme.outline),
                      )
                    : PageView.builder(
                        controller: _controller,
                        itemCount: gallery.length,
                        onPageChanged: (value) {
                          setState(() {
                            _pageIndex = value;
                          });
                        },
                        itemBuilder: (context, index) {
                          return Image.network(
                            gallery[index],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return ColoredBox(
                                color: shelfBg,
                                child: Icon(Icons.movie_outlined, size: 48, color: scheme.outline),
                              );
                            },
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
                Positioned(
                  left: 14,
                  top: 14,
                  child: Row(
                    children: [
                      if (widget.isTv) ...[
                        _HeroBadge(text: _tvSinceLabel(widget.detail)),
                        if (_factValue(widget.detail, 'Typical episode length').trim().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _HeroBadge(text: _factValue(widget.detail, 'Typical episode length')),
                        ],
                      ] else ...[
                        _HeroBadge(text: _extractYear(widget.detail)),
                        const SizedBox(width: 8),
                        _HeroBadge(text: _factValue(widget.detail, 'Runtime')),
                      ],
                    ],
                  ),
                ),
                if (gallery.length > 1 || widget.overlayActions != null)
                  Positioned(
                    top: 14,
                    right: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (gallery.length > 1)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var index = 0; index < gallery.length; index++)
                                Container(
                                  width: 7,
                                  height: 7,
                                  margin: const EdgeInsets.only(left: 6),
                                  decoration: BoxDecoration(
                                    color: index == _pageIndex
                                        ? scheme.onSurface
                                        : scheme.onSurface.withValues(alpha: 0.35),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        if (widget.overlayActions != null) ...[
                          if (gallery.length > 1) const SizedBox(height: 10),
                          widget.overlayActions!,
                        ],
                      ],
                    ),
                  ),
                if (widget.onShareTap != null)
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: _HeroShareButton(onPressed: widget.onShareTap!),
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
                    child: widget.detail.media.imageUrl == null ||
                            widget.detail.media.imageUrl!.isEmpty
                        ? ColoredBox(
                            color: posterBg,
                            child: Icon(Icons.movie_outlined, color: scheme.outline),
                          )
                        : Image.network(
                            widget.detail.media.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return ColoredBox(
                                color: posterBg,
                                child: Icon(Icons.movie_outlined, color: scheme.outline),
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
                      if (widget.isTv && _tvHeroSeasonEpisodePillsVisible(widget.detail)) ...[
                        _TvHeroSeasonEpisodePills(detail: widget.detail),
                        const SizedBox(height: 8),
                      ],
                      if (widget.detail.media.subtitle != null &&
                          widget.detail.media.subtitle!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            widget.detail.media.subtitle!,
                            style: CulturCatalogTypography.listMeta(
                              Theme.of(context),
                              scheme,
                            ),
                          ),
                        ),
                      Text(
                        widget.detail.media.title,
                        style: CulturCatalogTypography.listTitleBig(Theme.of(context)),
                      ),
                      if (widget.detail.crew.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        DetailDirectorPeopleCard(people: widget.detail.crew.expand((e) => e.people).toList()),
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

class _HeroShareButton extends StatelessWidget {
  const _HeroShareButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = context.culturTokens.radiusTight;

    return Tooltip(
      message: 'Copy link',
      child: Material(
        color: scheme.scrim.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(r),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.share_outlined, size: 20, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
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

String _extractYear(MovieCatalogDetail detail) {
  final release = _factValue(detail, 'Original release');
  if (release.length >= 4) {
    return release.substring(0, 4);
  }
  return '';
}

String _factValue(MovieCatalogDetail detail, String label) {
  for (final fact in detail.facts) {
    if (fact.label == label) {
      return fact.value;
    }
  }
  return '';
}

String _tvSinceLabel(MovieCatalogDetail detail) {
  final fa = _factValue(detail, 'First aired').trim();
  if (fa.length >= 4) {
    return 'Since ${fa.substring(0, 4)}';
  }
  for (final r in detail.ratings) {
    if (r.label == 'Premiere year' && r.value.trim().length >= 4) {
      return 'Since ${r.value.trim().substring(0, 4)}';
    }
  }
  return '';
}

bool _tvHeroSeasonEpisodePillsVisible(MovieCatalogDetail detail) {
  final seasons = _factValue(detail, 'Seasons').trim();
  final episodes = _factValue(detail, 'Episodes').replaceAll(',', '').trim();
  return seasons.isNotEmpty || episodes.isNotEmpty;
}

class _TvHeroSeasonEpisodePills extends StatelessWidget {
  const _TvHeroSeasonEpisodePills({required this.detail});

  final MovieCatalogDetail detail;

  @override
  Widget build(BuildContext context) {
    final seasons = _factValue(detail, 'Seasons').trim();
    final episodes = _factValue(detail, 'Episodes').replaceAll(',', '').trim();
    if (seasons.isEmpty && episodes.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = context.culturTokens.radiusTight;
    final style = CulturCatalogTypography.gridTitle(theme).copyWith(
      color: scheme.onSurface,
      letterSpacing: 0.3,
    );
    final iconColor = scheme.onSurface.withValues(alpha: 0.95);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.scrim.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (seasons.isNotEmpty) ...[
              Icon(Icons.calendar_view_week_outlined, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(seasons, style: style),
            ],
            if (seasons.isNotEmpty && episodes.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '|',
                  style: style.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ],
            if (episodes.isNotEmpty) ...[
              Icon(Icons.tv_outlined, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(episodes, style: style),
            ],
          ],
        ),
      ),
    );
  }
}
