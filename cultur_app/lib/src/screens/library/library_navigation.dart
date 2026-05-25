import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';

void openTvCustomListItem(BuildContext context, TvCustomListItem item) {
  final id = item.show.id;
  switch (item.entryKind) {
    case TvCustomListEntryKind.show:
      context.push('/tv/$id');
    case TvCustomListEntryKind.season:
      context.push('/tv/$id/seasons/${item.seasonNumber}');
    case TvCustomListEntryKind.episode:
      context.push('/tv/$id/seasons/${item.seasonNumber}/episodes/${item.episodeNumber}');
  }
}
