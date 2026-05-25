import 'package:flutter/material.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_image.dart';

/// @deprecated Prefer [CulturPosterImage] directly.
class MoviePosterThumb extends StatelessWidget {
  const MoviePosterThumb({
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.borderRadius,
    super.key,
  });

  final String? imageUrl;
  final double width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return CulturPosterImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}
