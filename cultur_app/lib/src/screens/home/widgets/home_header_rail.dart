import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_category.dart';
import 'package:yamtrack/src/screens/home/widgets/category_rail_chip.dart';

class HomeHeaderRail extends StatelessWidget {
  const HomeHeaderRail({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  final List<AppCategory> categories;
  final String selectedCategoryId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final railHeight = CategoryRailChip.kRailHeight;
        final railWidth = constraints.maxWidth;

        return SizedBox(
          height: railHeight,
          width: railWidth,
          child: AnimatedSize(
            duration: CategoryRailChip.animationDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: railHeight,
              width: railWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final category in categories)
                    CategoryRailChip(
                      key: ValueKey<String>(category.id),
                      category: category,
                      isSelected: category.id == selectedCategoryId,
                      onTap: () => onSelected(category.id),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
