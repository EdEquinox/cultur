import 'package:flutter/material.dart';

enum CatalogBrowseKind { movies, tv, games, boardgames, books, albums }

class AppCategory {
  const AppCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}
