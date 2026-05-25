import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/games/stash_game_event.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_image.dart';

/// Poster chip in the games events timeline strip (matches [UpcomingPosterCard]).
class StashEventPosterCard extends StatelessWidget {
  const StashEventPosterCard({
    required this.event,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  static const double width = 92;
  static const double height = 138;

  final StashGameEvent event;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.culturTokens;
    final borderColor = isSelected ? theme.colorScheme.primary : Colors.transparent;

    return InkWell(
      borderRadius: tokens.borderRadiusTight,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: tokens.borderRadiusTight,
          border: Border.all(color: borderColor, width: 2),
        ),
        child: ClipRRect(
          borderRadius: tokens.borderRadiusTight,
          child: CulturPosterImage(
            imageUrl: event.imageUrl,
            width: width,
            height: height,
            borderRadius: tokens.borderRadiusTight,
            mediaType: 'game',
          ),
        ),
      ),
    );
  }
}
