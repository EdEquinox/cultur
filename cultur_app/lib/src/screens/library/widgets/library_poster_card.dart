import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/widgets/cards/cultur_media_card_content.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_card.dart';

class LibraryPosterCard extends StatelessWidget {
  const LibraryPosterCard({
    required this.item,
    super.key,
    this.onTap,
    this.onLongPress,
  });

  final TrackingItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return CulturPosterCard(
      content: CulturMediaCardContent.fromTracking(item),
      onTap: onTap,
      onLongPress: onLongPress,
      posterRadius: BorderRadius.circular(18),
    );
  }
}
