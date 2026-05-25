import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/utils/igdb_image_url.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_size.dart';

/// Shared poster / still image with placeholder and error handling.
class CulturPosterImage extends StatelessWidget {
  const CulturPosterImage({
    required this.imageUrl,
    super.key,
    this.width,
    this.height,
    this.preset,
    this.borderRadius,
    this.mediaType,
    this.fit = BoxFit.cover,
  }) : assert(
          (width != null && height != null) || preset != null,
          'Provide width/height or a CulturPosterSizePreset',
        );

  final String? imageUrl;
  final double? width;
  final double? height;
  final CulturPosterSizePreset? preset;
  final BorderRadius? borderRadius;
  final String? mediaType;
  final BoxFit fit;

  double get _width => width ?? preset!.width;
  double get _height => height ?? preset!.height;

  String? get _displayUrl => igdbDisplayImageUrl(imageUrl);

  @override
  Widget build(BuildContext context) {
    final tokens = context.culturTokens;
    final radius = borderRadius ?? tokens.borderRadiusTight;
    final scheme = Theme.of(context).colorScheme;
    final placeholderColor = scheme.surfaceContainerHigh;

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: _width,
        height: _height,
        child: _hasImage
            ? Image.network(
                _displayUrl!,
                fit: fit,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) => _Placeholder(
                  color: placeholderColor,
                  icon: _placeholderIcon,
                ),
              )
            : _Placeholder(
                color: placeholderColor,
                icon: _placeholderIcon,
              ),
      ),
    );
  }

  bool get _hasImage => _displayUrl != null && _displayUrl!.isNotEmpty;

  IconData get _placeholderIcon {
    final type = mediaType?.trim().toLowerCase();
    return switch (type) {
      'tv' || 'series' || 'show' => Icons.tv_outlined,
      'game' || 'games' => Icons.sports_esports_outlined,
      'book' || 'books' => Icons.menu_book_outlined,
      'person' => Icons.person_outline,
      _ => Icons.movie_outlined,
    };
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color),
      child: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
