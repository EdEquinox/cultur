import 'package:flutter/material.dart';

import '../../movies/movie_detail/movie_detail_page.dart';

/// TV series detail route; shares implementation with [MovieDetailPage].
class SeriesDetailPage extends StatelessWidget {
  const SeriesDetailPage({required this.mediaId, super.key});

  final String mediaId;

  @override
  Widget build(BuildContext context) {
    return MovieDetailPage(mediaId: mediaId, isTv: true);
  }
}
