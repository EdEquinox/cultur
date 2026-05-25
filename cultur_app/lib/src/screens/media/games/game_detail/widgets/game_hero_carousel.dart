import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Game detail hero: gallery, year badge, title and poster — no IGDB/user ratings.
class GameHeroCarousel extends StatefulWidget {
  const GameHeroCarousel({
    super.key,
    required this.detail,
    this.overlayActions,
    this.onShareTap,
  });

  final CatalogDetail detail;

  /// Shown below the slideshow dots (top-right), e.g. priority pin.
  final Widget? overlayActions;

  /// Copy-link action on the bottom-right of the backdrop.
  final VoidCallback? onShareTap;

  @override
  State<GameHeroCarousel> createState() => _GameHeroCarouselState();
}

class _GameHeroCarouselState extends State<GameHeroCarousel> {
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

  String get _yearLabel {
    final release = widget.detail.factValue('Release').trim();
    if (release.length >= 4) {
      return release.substring(0, 4);
    }
    return release;
  }

  String get _platformsLabel {
    return widget.detail.factValue('Platforms').trim();
  }

  String get _gameTypeLabel {
    return widget.detail.gameType?.trim() ?? '';
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
    final gameType = _gameTypeLabel;
    final platforms = _platformsLabel;

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
                        child: Icon(Icons.sports_esports_outlined, size: 48, color: scheme.outline),
                      )
                    : PageView.builder(
                        controller: _controller,
                        itemCount: gallery.length,
                        onPageChanged: (value) => setState(() => _pageIndex = value),
                        itemBuilder: (context, index) {
                          return Image.network(
                            gallery[index],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return ColoredBox(
                                color: shelfBg,
                                child: Icon(
                                  Icons.sports_esports_outlined,
                                  size: 48,
                                  color: scheme.outline,
                                ),
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
                if (year.isNotEmpty || gameType.isNotEmpty)
                  Positioned(
                    left: 14,
                    top: 14,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (year.isNotEmpty) _HeroBadge(text: year),
                        if (year.isNotEmpty && gameType.isNotEmpty) const SizedBox(width: 6),
                        if (gameType.isNotEmpty) _HeroBadge(text: gameType),
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
                    child: GameHeroOverlayPinButton(
                      icon: Icons.share_outlined,
                      tooltip: 'Copy link',
                      onPressed: widget.onShareTap,
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
                    child: widget.detail.media.imageUrl == null ||
                            widget.detail.media.imageUrl!.isEmpty
                        ? ColoredBox(
                            color: posterBg,
                            child: Icon(Icons.sports_esports_outlined, color: scheme.outline),
                          )
                        : Image.network(
                            widget.detail.media.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return ColoredBox(
                                color: posterBg,
                                child: Icon(Icons.sports_esports_outlined, color: scheme.outline),
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
                      if (platforms.isNotEmpty) ...[
                        _HeroPlatformsChip(text: platforms),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        widget.detail.media.title,
                        style: CulturCatalogTypography.listTitleBig(Theme.of(context)),
                      ),
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

/// Priority / quick-action pin on the game hero (below slideshow dots).
class GameHeroOverlayPinButton extends StatelessWidget {
  const GameHeroOverlayPinButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = context.culturTokens.radiusTight;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.scrim.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(r),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _HeroPlatformsChip extends StatelessWidget {
  const _HeroPlatformsChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = context.culturTokens.radiusTight;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.scrim.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(r),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CulturCatalogTypography.gridTitle(Theme.of(context)).copyWith(
            color: scheme.onSurface.withValues(alpha: 0.92),
          ),
        ),
      ),
    );
  }
}
