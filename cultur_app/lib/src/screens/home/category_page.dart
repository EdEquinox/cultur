import 'package:flutter/material.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/media/boardgames/home/boardgames_page.dart';
import 'package:yamtrack/src/screens/media/albums/home/albums_page.dart';
import 'package:yamtrack/src/screens/media/books/home/books_page.dart';
import 'package:yamtrack/src/screens/media/games/home/games_page.dart';
import 'package:yamtrack/src/screens/media/movies/home/movies_page.dart';
import 'package:yamtrack/src/screens/media/shows/home/shows_page.dart';
import 'package:yamtrack/src/utils/home_categories.dart';

class CategoryPage extends StatelessWidget {
  const CategoryPage({
    required this.categoryId,
    this.initialQuery = '',
    this.initialGenre = '',
    this.initialKeyword = '',
    this.initialSection = '',
    this.initialCompanyId = '',
    this.initialCompanyRole = '',
    this.initialCompanyName = '',
    this.initialFranchiseId = '',
    this.initialCollectionId = '',
    this.initialBrowseName = '',
    super.key,
  });

  final String categoryId;
  final String initialQuery;
  final String initialGenre;
  final String initialKeyword;
  final String initialSection;
  final String initialCompanyId;
  final String initialCompanyRole;
  final String initialCompanyName;
  final String initialFranchiseId;
  final String initialCollectionId;
  final String initialBrowseName;

  @override
  Widget build(BuildContext context) {
    final category = catalogCategoryById(categoryId);
    if (category == null) {
      return const Scaffold(
        body: EmptyState(
          title: 'Unknown category',
          message: 'That category does not exist yet.',
          icon: Icons.category_outlined,
        ),
      );
    }

    switch (category.id) {
      case 'movies':
        return MoviesPage(
          initialQuery: initialQuery,
          initialGenre: initialGenre,
          initialKeyword: initialKeyword,
          initialSection: initialSection,
        );
      case 'series':
        return ShowsPage(
          initialQuery: initialQuery,
          initialGenre: initialGenre,
          initialKeyword: initialKeyword,
          initialSection: initialSection,
        );
      case 'books':
        return BooksPage(
          initialQuery: initialQuery,
          initialSection: initialSection,
        );
      case 'albums':
        return AlbumsPage(
          initialQuery: initialQuery,
          initialSection: initialSection,
        );
      case 'games':
        return GamesPage(
          initialQuery: initialQuery,
          initialSection: initialSection,
          initialCompanyId: initialCompanyId,
          initialCompanyRole: initialCompanyRole,
          initialCompanyName: initialCompanyName,
          initialFranchiseId: initialFranchiseId,
          initialCollectionId: initialCollectionId,
          initialBrowseName: initialBrowseName,
        );
        case 'board-games':
        return BoardgamesPage(
          initialQuery: initialQuery,
          initialSection: initialSection,
        );
      default:
        return const Scaffold(
          body: EmptyState(
            title: 'Unknown category',
            message: 'That category does not exist yet.',
            icon: Icons.category_outlined,
          ),
        );
    }
  }
}
