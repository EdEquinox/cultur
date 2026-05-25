import 'package:flutter/material.dart';

import 'action_tile_widget.dart';

/// One button in a [CulturDetailActionRow].
class CulturDetailActionTileSpec {
  const CulturDetailActionTileSpec({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  const CulturDetailActionTileSpec.toggle({
    required IconData selectedIcon,
    required IconData outlinedIcon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.subtitle,
  }) : icon = selected ? selectedIcon : outlinedIcon;

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final String? subtitle;
}

/// Full-width detail action bar shared by movies, TV, games, books, and board games.
class CulturDetailActionRow extends StatelessWidget {
  const CulturDetailActionRow({
    super.key,
    required this.tiles,
    this.enabled = true,
    this.gap = 4,
    this.horizontalPadding = 4,
    this.below,
  });

  final List<CulturDetailActionTileSpec> tiles;
  final bool enabled;
  final double gap;
  final double horizontalPadding;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) {
      return below ?? const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final spec = tiles[i];
                      return ActionTile(
                        width: constraints.maxWidth,
                        icon: spec.icon,
                        tooltip: spec.tooltip,
                        selected: spec.selected,
                        enabled: enabled,
                        onTap: spec.onTap,
                        subtitle: spec.subtitle,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        ?below,
      ],
    );
  }
}
