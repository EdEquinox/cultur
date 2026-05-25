import 'package:flutter/material.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_image.dart';

/// @deprecated Prefer [CulturPosterImage] directly.
class LibraryPosterThumb extends StatelessWidget {
  const LibraryPosterThumb({
    required this.imageUrl,
    required this.width,
    required this.height,
    super.key,
    this.radius = 4,
  });

  final String? imageUrl;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CulturPosterImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(radius),
    );
  }
}
