import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// TMDB website URLs and launching helpers (reusable across TV/movie flows).
abstract final class TmdbLinks {
  static String? normalizeExternalId(String? raw) {
    final t = raw?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// `https://www.themoviedb.org/tv/{id}`
  static Uri? tvShow(String? tvExternalId) {
    final id = normalizeExternalId(tvExternalId);
    if (id == null) {
      return null;
    }
    return Uri.parse('https://www.themoviedb.org/tv/$id');
  }

  /// `https://www.themoviedb.org/tv/{id}/season/{n}`
  static Uri? tvSeason(String? tvExternalId, int seasonNumber) {
    final id = normalizeExternalId(tvExternalId);
    if (id == null) {
      return null;
    }
    return Uri.parse('https://www.themoviedb.org/tv/$id/season/$seasonNumber');
  }

  /// `https://www.themoviedb.org/tv/{id}/season/{sn}/episode/{en}`
  static Uri? tvEpisode(String? tvExternalId, int seasonNumber, int episodeNumber) {
    final id = normalizeExternalId(tvExternalId);
    if (id == null) {
      return null;
    }
    return Uri.parse('https://www.themoviedb.org/tv/$id/season/$seasonNumber/episode/$episodeNumber');
  }

  /// `https://www.themoviedb.org/movie/{id}`
  static Uri? movie(String? movieExternalId) {
    final id = normalizeExternalId(movieExternalId);
    if (id == null) {
      return null;
    }
    return Uri.parse('https://www.themoviedb.org/movie/$id');
  }

  static Future<bool> launchExternal(Uri? uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
    if (uri == null) {
      return false;
    }
    return launchUrl(uri, mode: mode);
  }

  /// Opens [uri] in an external handler; shows [failureMessage] if launch fails or [uri] is null.
  static Future<void> launchWithSnackBarOnFailure(
    BuildContext context,
    Uri? uri, {
    String failureMessage = 'Could not open the link.',
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    if (uri == null) {
      return;
    }
    final ok = await launchExternal(uri, mode: mode);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }
}
