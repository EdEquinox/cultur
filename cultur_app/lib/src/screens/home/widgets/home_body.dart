import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/catalog/catalog_category.dart';
import 'package:yamtrack/src/screens/media/movies/home/movies_category_home.dart';
import 'package:yamtrack/src/screens/media/boardgames/home/boardgames_category_home.dart';
import 'package:yamtrack/src/screens/media/albums/home/albums_category_home.dart';
import 'package:yamtrack/src/screens/media/books/home/books_category_home.dart';
import 'package:yamtrack/src/screens/media/games/home/games_category_home.dart';
import 'package:yamtrack/src/screens/media/shows/home/shows_category_home.dart';

class HomeBody extends ConsumerWidget {
  const HomeBody({super.key, 
    required this.category,
    required this.username,
  });

  final AppCategory category;
  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (category.id) {
      case 'movies':
        return MoviesCategoryHomeBody(username: username);
      case 'series':
        return ShowsCategoryHomeBody(username: username);
      case 'games':
        return GamesCategoryHomeBody(username: username);
      case 'board-games':
        return BoardgamesCategoryHomeBody(username: username);
      case 'books':
        return BooksCategoryHomeBody(username: username);
      case 'albums':
        return AlbumsCategoryHomeBody(username: username);
      default:
        return const SizedBox.shrink();
    }
  }
}
