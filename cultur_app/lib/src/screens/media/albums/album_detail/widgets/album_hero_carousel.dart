import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail_person.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_hero_carousel.dart';
import 'package:yamtrack/src/screens/widgets/movie_crew_chip.dart';
import 'package:yamtrack/src/utils/musicbrainz_person_utils.dart';
import 'package:yamtrack/src/utils/person_route_utils.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Album detail hero — gallery, year/format/rating badges, title and artist.
class AlbumHeroCarousel extends StatefulWidget {
  const AlbumHeroCarousel({
    super.key,
    required this.detail,
    this.overlayActions,
    this.onShareTap,
  });

  final CatalogDetail detail;
  final Widget? overlayActions;
  final VoidCallback? onShareTap;

  @override
  State<AlbumHeroCarousel> createState() => _AlbumHeroCarouselState();
}

class _AlbumHeroCarouselState extends State<AlbumHeroCarousel> {
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

  String get _yearLabel {
    final release = widget.detail.factValue('Release').trim();
    if (release.length >= 4) {
      return release.substring(0, 4);
    }
    final year = widget.detail.media.metadata['year'];
    if (year != null) {
      return year.toString().trim();
    }
    return release;
  }

  String get _ratingLabel {
    for (final rating in widget.detail.ratings) {
      final parsed = double.tryParse(rating.value.trim());
      if (parsed != null && parsed > 0) {
        final label = rating.label.trim();
        return label.isEmpty ? rating.value.trim() : '$label: ${rating.value.trim()}';
      }
    }
    final community = widget.detail.media.metadata['communityRating'];
    if (community is num && community > 0) {
      return 'Rating: ${community.toStringAsFixed(1)}';
    }
    return '';
  }

  String get _formatLabel {
    final formats = widget.detail.media.metadata['formatTypes'];
    if (formats is List && formats.isNotEmpty) {
      return formats.first.toString().trim();
    }
    return '';
  }

  List<CatalogDetailPerson> get _artistPeople {
    if (widget.detail.cast.isNotEmpty) {
      return widget.detail.cast;
    }
    final artists = widget.detail.media.metadata['artists'];
    if (artists is! List) {
      return const [];
    }
    final people = <CatalogDetailPerson>[];
    for (final row in artists) {
      if (row is! Map) {
        continue;
      }
      final name = row['name']?.toString().trim() ?? '';
      if (name.isEmpty) {
        continue;
      }
      final rawId = row['id']?.toString().trim() ?? '';
      people.add(
        CatalogDetailPerson(
          personId: rawId.isNotEmpty ? musicArtistPersonId(rawId) : null,
          name: name,
          role: 'Artist',
          imageUrl: row['imageUrl']?.toString(),
        ),
      );
    }
    if (people.isEmpty) {
      final subtitle = widget.detail.media.subtitle?.trim();
      final metaArtist = widget.detail.media.metadata['artistName']?.toString().trim() ?? '';
      final label = (subtitle != null && subtitle.isNotEmpty)
          ? subtitle
          : metaArtist;
      if (label.isNotEmpty) {
        people.add(CatalogDetailPerson(name: label, role: 'Artist'));
      }
    }
    return people;
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
    final year = _yearLabel;
    final rating = _ratingLabel;
    final format = _formatLabel.toLowerCase();
    final artistPeople = _artistPeople;
    final primaryArtistChip = artistPeople.isEmpty
        ? null
        : MovieCrewChip(
            person: artistPeople.first,
            onTap: artistPeople.first.personId != null &&
                    artistPeople.first.personId!.isNotEmpty
                ? () => context.push(
                      personAppRoutePath(artistPeople.first.personId!),
                    )
                : null,
          );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
                        child: Icon(Icons.album_outlined, size: 48, color: scheme.outline),
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
                                child: Icon(Icons.album_outlined, size: 48, color: scheme.outline),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (year.isNotEmpty || format.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (year.isNotEmpty) _AlbumHeroBadge(text: year),
                            if (year.isNotEmpty && format.isNotEmpty) const SizedBox(width: 6),
                            if (format.isNotEmpty)
                              _AlbumHeroBadge(text: format),
                          ],
                        ),
                      if (rating.isNotEmpty) ...[
                        if (year.isNotEmpty || format.isNotEmpty) const SizedBox(height: 6),
                        _AlbumHeroBadge(text: rating),
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
                    height: 84,
                    child: widget.detail.media.imageUrl == null ||
                            widget.detail.media.imageUrl!.isEmpty
                        ? ColoredBox(
                            color: posterBg,
                            child: Icon(Icons.album_outlined, color: scheme.outline),
                          )
                        : Image.network(
                            widget.detail.media.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return ColoredBox(
                                color: posterBg,
                                child: Icon(Icons.album_outlined, color: scheme.outline),
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
                        widget.detail.media.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: CulturCatalogTypography.listTitleBig(Theme.of(context)),
                      ),
                      if (primaryArtistChip != null) ...[
                        const SizedBox(height: 8),
                        primaryArtistChip,
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

class _AlbumHeroBadge extends StatelessWidget {
  const _AlbumHeroBadge({required this.text});

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
