import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_category.dart';

class CategoryRailChip extends StatefulWidget {
  const CategoryRailChip({
    super.key,
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final AppCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  static const Duration animationDuration = Duration(milliseconds: 360);
  static const Duration _animDuration = animationDuration;
  static const double kIconSize = 18;
  static const double kVerticalPad = 6;
  /// Min height: icon + vertical padding + room for label line / border.
  static const double kRailHeight = 44;

  @override
  State<CategoryRailChip> createState() => CategoryRailChipState();
}

class CategoryRailChipState extends State<CategoryRailChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final CurvedAnimation _expand;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: CategoryRailChip._animDuration);
    _expand = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _ctrl.value = widget.isSelected ? 1.0 : 0.0;
  }

  @override
  void didUpdateWidget(covariant CategoryRailChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.category.id != oldWidget.category.id) {
      _ctrl.value = widget.isSelected ? 1.0 : 0.0;
      return;
    }
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _expand.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _expand,
          builder: (context, child) {
            final t = _expand.value.clamp(0.0, 1.0);
            // widthFactor 0 can confuse intrinsic sizing; use a tiny floor when collapsed.
            final widthFactor = t < 0.001 ? 0.001 : t;
            final bg = Color.lerp(
              theme.colorScheme.surfaceContainerHigh,
              theme.colorScheme.primaryContainer,
              t,
            )!;
            final borderColor = Color.lerp(
              theme.colorScheme.outlineVariant,
              theme.colorScheme.primary,
              t,
            )!;
            final iconColor = Color.lerp(
              theme.colorScheme.onSurfaceVariant,
              theme.colorScheme.onPrimaryContainer,
              t,
            )!;
            final labelColor = Color.lerp(
              theme.colorScheme.onSurfaceVariant,
              theme.colorScheme.onPrimaryContainer,
              t,
            )!;

            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: 12.0 + 2.0 * t,
                vertical: CategoryRailChip.kVerticalPad,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  width: 1.0 + 0.5 * t,
                  color: borderColor,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    widget.category.icon,
                    size: CategoryRailChip.kIconSize,
                    color: iconColor,
                  ),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: widthFactor,
                      child: Padding(
                        padding: EdgeInsets.only(left: 6.0 * t),
                        child: Opacity(
                          opacity: t,
                          child: Text(
                            widget.category.title,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: labelColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

