import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/library/library_tracking_filter_model.dart';
import 'package:yamtrack/src/models/library/library_enums.dart';
import 'package:yamtrack/src/screens/library/widgets/library_filter_option.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

List<LibraryFilterOption> buildLibraryTrackingFilterOptions({
  required BuildContext context,
  required LibraryFilterSurface surface,
  required LibraryMediaScope mediaScope,
  required LibraryTrackingFilterModel model,
  required ValueChanged<LibraryTrackingFilterModel> onModelChanged,
  LibraryCollectionKind? trackingCollectionKind,
}) {
  final options = <LibraryFilterOption>[
    LibraryFilterOption(
      id: 'genres',
      label: model.genreSlugs.isEmpty ? 'Genres' : 'Genres (${model.genreSlugs.length})',
      isActive: model.genreSlugs.isNotEmpty,
      onPick: (ctx) => showMultiSelectKeySheet(
        ctx,
        title: 'Genres',
        keyLabels: genrePickList,
        selected: model.genreSlugs,
        onApply: (next) {
          model.genreSlugs = next;
          onModelChanged(model);
        },
      ),
    ),
  ];

  if (surface == LibraryFilterSurface.tracking && trackingCollectionKind != null) {
    final k = trackingCollectionKind;
    if (k == LibraryCollectionKind.finished) {
      options.add(
        LibraryFilterOption(
          id: 'watched_date',
          label: watchedDateChipLabel(model.watchedDatePreset),
          isActive: model.watchedDatePreset != WatchedDatePreset.none,
          onPick: (ctx) => showWatchedDatePresetSheet(
            ctx,
            model.watchedDatePreset,
            (v) {
              model.watchedDatePreset = v;
              onModelChanged(model);
            },
          ),
        ),
      );
    }
    if (k == LibraryCollectionKind.owned) {
      options.add(
        LibraryFilterOption(
          id: 'format',
          label: model.metadataFilterActive && model.metadataMediumKeys.isNotEmpty
              ? 'Format (${model.metadataMediumKeys.length})'
              : 'Format',
          isActive: model.metadataFilterActive && model.metadataMediumKeys.isNotEmpty,
          onPick: (ctx) => showMultiSelectKeySheet(
            ctx,
            title: 'Owned format',
            keyLabels: metadataMediumLabels,
            selected: model.metadataMediumKeys,
            onApply: (next) {
              model.metadataMediumKeys = next;
              model.metadataFilterActive = next.isNotEmpty;
              onModelChanged(model);
            },
          ),
        ),
      );
    }
    if (mediaScope == LibraryMediaScope.tv) {
      options.add(
        LibraryFilterOption(
          id: 'tv_rating',
          label: tvRatingFilterChipLabel(model),
          isActive: model.tvRatingFilterEnabled || model.tvTmdbRatingFilterEnabled,
          onPick: (ctx) => showTvRatingFilterSheet(ctx, model, onModelChanged),
        ),
      );
      options.add(
        LibraryFilterOption(
          id: 'show_status',
          label: model.tvShowStatusFilterActive && model.tvShowStatusKeys.isNotEmpty
              ? 'Status (${model.tvShowStatusKeys.length})'
              : 'Show status',
          isActive: model.tvShowStatusFilterActive && model.tvShowStatusKeys.isNotEmpty,
          onPick: (ctx) => showMultiSelectKeySheet(
            ctx,
            title: 'Show status',
            keyLabels: kTvShowStatusLabels,
            selected: model.tvShowStatusKeys,
            onApply: (next) {
              model.tvShowStatusKeys = next;
              model.tvShowStatusFilterActive = next.isNotEmpty;
              onModelChanged(model);
            },
          ),
        ),
      );
      options.add(
        LibraryFilterOption(
          id: 'show_type',
          label: model.tvShowTypeFilterActive && model.tvShowTypeKeys.isNotEmpty
              ? 'Type (${model.tvShowTypeKeys.length})'
              : 'Show type',
          isActive: model.tvShowTypeFilterActive && model.tvShowTypeKeys.isNotEmpty,
          onPick: (ctx) => showMultiSelectKeySheet(
            ctx,
            title: 'Show type',
            keyLabels: kTvShowTypeLabels,
            selected: model.tvShowTypeKeys,
            onApply: (next) {
              model.tvShowTypeKeys = next;
              model.tvShowTypeFilterActive = next.isNotEmpty;
              onModelChanged(model);
            },
          ),
        ),
      );
    }
  }

  return options;
}
