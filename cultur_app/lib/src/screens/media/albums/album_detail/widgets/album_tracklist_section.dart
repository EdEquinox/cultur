import 'package:flutter/material.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

const int _kTracklistPreviewCount = 5;
const double _kTrackNumberColumnWidth = 40;

class AlbumTrackRow {
  const AlbumTrackRow({
    this.position,
    required this.title,
    this.duration,
  });

  final String? position;
  final String title;
  final String? duration;
}

List<AlbumTrackRow> albumTracksFromMetadata(Map<String, dynamic> metadata) {
  final raw = metadata['tracklist'];
  if (raw is! List) {
    return const [];
  }
  final rows = <AlbumTrackRow>[];
  for (final entry in raw) {
    if (entry is! Map) {
      continue;
    }
    final title = entry['title']?.toString().trim() ?? '';
    if (title.isEmpty) {
      continue;
    }
    final position = entry['position']?.toString().trim();
    final duration = entry['duration']?.toString().trim();
    rows.add(
      AlbumTrackRow(
        position: position != null && position.isNotEmpty ? position : null,
        title: title,
        duration: duration != null && duration.isNotEmpty ? duration : null,
      ),
    );
  }
  return rows;
}

class AlbumTracklistSection extends StatefulWidget {
  const AlbumTracklistSection({super.key, required this.tracks});

  final List<AlbumTrackRow> tracks;

  @override
  State<AlbumTracklistSection> createState() => _AlbumTracklistSectionState();
}

class _AlbumTracklistSectionState extends State<AlbumTracklistSection> {
  bool _expanded = false;

  bool get _canExpand => widget.tracks.length > _kTracklistPreviewCount;

  List<AlbumTrackRow> get _visibleTracks {
    if (_expanded || !_canExpand) {
      return widget.tracks;
    }
    return widget.tracks.take(_kTracklistPreviewCount).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tracks.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _visibleTracks;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tracklist',
              style: CulturCatalogTypography.sectionHeading(theme),
            ),
            const SizedBox(height: 12),
            ...visible.asMap().entries.map((entry) {
              final index = entry.key;
              final track = entry.value;
              final positionLabel = track.position ?? '${index + 1}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: _kTrackNumberColumnWidth,
                      child: Text(
                        positionLabel,
                        textAlign: TextAlign.right,
                        style: CulturCatalogTypography.gridSubtitle(theme, scheme),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        track.title,
                        style: CulturCatalogTypography.bodyText(theme, scheme),
                      ),
                    ),
                    if (track.duration != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        track.duration!,
                        style: CulturCatalogTypography.gridSubtitle(theme, scheme),
                      ),
                    ],
                  ],
                ),
              );
            }),
            if (_canExpand)
              Align(
                alignment: Alignment.center,
                child: IconButton(
                  tooltip: _expanded ? 'Show less' : 'Show all tracks',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
