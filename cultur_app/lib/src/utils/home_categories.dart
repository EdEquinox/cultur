import 'package:yamtrack/src/models/catalog/catalog_category.dart';
import 'package:flutter/material.dart';

String normalizedCatalogSection(CatalogBrowseKind kind, String raw) {
  final s = raw.trim().toLowerCase();
  if (kind == CatalogBrowseKind.tv) {
    const allowed = {'popular', 'on_the_air', 'top_rated', 'airing_today'};
    return allowed.contains(s) ? s : 'popular';
  }
  if (kind == CatalogBrowseKind.games) {
    const allowed = {'popular', 'top_rated', 'upcoming', 'recent'};
    return allowed.contains(s) ? s : 'popular';
  }
  if (kind == CatalogBrowseKind.boardgames) {
    const allowed = {'popular', 'hot'};
    return allowed.contains(s) ? s : 'popular';
  }
  if (kind == CatalogBrowseKind.books) {
    const allowed = {'popular', 'trending', 'top_rated'};
    return allowed.contains(s) ? s : 'popular';
  }
  if (kind == CatalogBrowseKind.albums) {
    const allowed = {'popular', 'trending', 'search'};
    return allowed.contains(s) ? s : 'search';
  }
  const allowed = {'popular', 'now_playing', 'top_rated', 'upcoming'};
  return allowed.contains(s) ? s : 'popular';
}

const catalogCategories = <AppCategory>[
  AppCategory(
    id: 'movies',
    title: 'Movies',
    subtitle: 'Cinema and new releases',
    icon: Icons.movie_outlined,
  ),
  AppCategory(
    id: 'series',
    title: 'TV Shows',
    subtitle: 'TV and streaming',
    icon: Icons.live_tv_outlined,
  ),
  AppCategory(
    id: 'games',
    title: 'Games',
    subtitle: 'Video games',
    icon: Icons.sports_esports_outlined,
  ),
  AppCategory(
    id: 'books',
    title: 'Books',
    subtitle: 'Reading and backlog',
    icon: Icons.menu_book_outlined,
  ),
  AppCategory(
    id: 'albums',
    title: 'Albums',
    subtitle: 'Music releases',
    icon: Icons.album_outlined,
  ),
  AppCategory(
    id: 'board-games',
    title: 'Board Games',
    subtitle: 'Board games',
    icon: Icons.casino_outlined,
  ),
];

AppCategory? catalogCategoryById(String id) {
  for (final category in catalogCategories) {
    if (category.id == id) {
      return category;
    }
  }
  return null;
}
