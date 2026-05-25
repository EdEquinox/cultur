import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/games/game_home_shelf_item.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/home/widgets/shelf_heading.dart';
import 'package:yamtrack/src/screens/media/books/home/widgets/book_reading_shelf_row.dart';

class BooksReadingShelfSection extends StatelessWidget {
  const BooksReadingShelfSection({
    super.key,
    required this.title,
    required this.state,
    required this.username,
    required this.emptyMessage,
    this.onSeeAll,
  });

  final String title;
  final AsyncValue<List<GameHomeShelfItem>> state;
  final String username;
  final String emptyMessage;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeading(title: title, icon: Icons.menu_book_outlined, onSeeAll: onSeeAll),
        const SizedBox(height: 12),
        state.when(
          loading: () => const SizedBox(
            height: BookReadingShelfRow.height,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => SizedBox(
            height: 160,
            child: ErrorState(error: error),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: EmptyState(
                  title: 'Nothing here',
                  message: emptyMessage,
                  icon: Icons.menu_book_outlined,
                ),
              );
            }
            return SizedBox(
              height: BookReadingShelfRow.height,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  return BookReadingShelfRow(
                    item: items[index],
                    username: username,
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
