import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/home/widgets/shelf_heading.dart';
import 'package:yamtrack/src/screens/home/widgets/latest_release_card.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

class LatestReleaseSection extends StatelessWidget {
  const LatestReleaseSection({
    super.key,
    required this.title,
    required this.icon,
    required this.state,
    required this.emptyMessage,
    this.onSeeAll,
  });

  final String title;
  final IconData icon;
  final AsyncValue<CatalogListData> state;
  final String emptyMessage;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeading(title: title, icon: icon, onSeeAll: onSeeAll),
        const SizedBox(height: 12),
        state.when(
          loading: () => const SizedBox(
            height: 164,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => SizedBox(
            height: 180,
            child: ErrorState(error: error),
          ),
          data: (data) {
            if (data.items.isEmpty) {
              return SizedBox(
                height: 140,
                child: EmptyState(
                  title: title,
                  message: emptyMessage,
                  icon: icon,
                ),
              );
            }

            return SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: data.items.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = data.items[index];
                  return LatestReleaseCard(
                    item: item,
                    onTap: () => context.push(catalogItemDetailPath(item)),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
