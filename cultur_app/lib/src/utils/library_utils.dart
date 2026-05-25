import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

/// Fixed IDs for lists managed by the app (priority queue + cinema).
abstract final class BuiltInMovieLists {
  static const String priorityListId = '__builtin_priority_queue';
  static const String cinemaListId = '__builtin_cinema_queue';
  static const String pendingImportsListId = '__builtin_movie_pending_imports';

  static const String priorityListName = 'Priority queue';
  static const String cinemaListName = 'Movies in cinema';
  static const String pendingImportsListName = 'Pending imports';

  static bool isBuiltIn(String id) =>
      id == priorityListId || id == cinemaListId || id == pendingImportsListId;

  static bool isPendingImportsList(String id) => id == pendingImportsListId;
}

abstract final class BuiltInTvLists {
  static const String pendingImportsListId = '__builtin_tv_pending_imports';

  static const String pendingImportsListName = 'Pending imports';

  static bool isBuiltIn(String id) => id == pendingImportsListId;

  static bool isPendingImportsList(String id) => id == pendingImportsListId;
}

/// Fixed IDs for game lists managed by the app (priority queue + pending imports).
abstract final class BuiltInGameLists {
  static const String priorityListId = '__builtin_game_priority_queue';
  static const String pendingImportsListId = '__builtin_game_pending_imports';

  static const String priorityListName = 'Priority queue';
  static const String pendingImportsListName = 'Pending imports';

  static bool isBuiltIn(String id) =>
      id == priorityListId || id == pendingImportsListId;

  static bool isPriorityList(String id) => id == priorityListId;

  static bool isPendingImportsList(String id) => id == pendingImportsListId;
}

abstract final class BuiltInBoardgameLists {
  static const String priorityListId = '__builtin_boardgame_priority_queue';

  static const String priorityListName = 'Priority queue';

  static bool isBuiltIn(String id) => id == priorityListId;
}

abstract final class BuiltInBookLists {
  static const String priorityListId = '__builtin_book_priority_queue';
  static const String pendingImportsListId = '__builtin_book_pending_imports';

  static const String priorityListName = 'Priority queue';
  static const String pendingImportsListName = 'Pending imports';

  static bool isBuiltIn(String id) =>
      id == priorityListId || id == pendingImportsListId;

  static bool isPendingImportsList(String id) => id == pendingImportsListId;
}

abstract final class BuiltInMusicLists {
  static const String priorityListId = '__builtin_music_priority_queue';
  static const String pendingImportsListId = '__builtin_music_pending_imports';

  static const String priorityListName = 'Priority queue';
  static const String pendingImportsListName = 'Pending imports';

  static bool isBuiltIn(String id) =>
      id == priorityListId || id == pendingImportsListId;

  static bool isPriorityList(String id) => id == priorityListId;

  static bool isPendingImportsList(String id) => id == pendingImportsListId;
}

/// True when [media] has a release date strictly after today (not yet in theatres / digital).
bool catalogItemNotYetReleased(CatalogItem media) {
  final raw = media.metadata['releaseDate']?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return false;
  }
  final parsed = DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
  if (parsed == null) {
    return false;
  }
  final release = DateTime(parsed.year, parsed.month, parsed.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return release.isAfter(today);
}

/// True when [media] has a release date on or before today and within the last [days] days.
bool catalogItemReleasedWithinLastDays(CatalogItem media, {int days = 30}) {
  final raw = media.metadata['releaseDate']?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return false;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return false;
  }
  final release = DateTime(parsed.year, parsed.month, parsed.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (release.isAfter(today)) {
    return false;
  }
  final threshold = today.subtract(Duration(days: days));
  return !release.isBefore(threshold);
}


bool isAccentCatalogMetaPart(String part) =>
    part == 'Movie' ||
    part == 'Series' ||
    part == 'Episode' ||
    part == 'Game' ||
    part == 'Book' ||
    part == 'Board game';

void scheduleTextEditingControllerDispose(TextEditingController controller) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    controller.dispose();
  });
}
