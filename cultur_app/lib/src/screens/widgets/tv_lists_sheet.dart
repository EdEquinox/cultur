import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/models/lists/tv_custom_lists_data.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';

/// Bottom sheet: add/remove the current TV scope (series, season, or episode) on any custom TV list.
class TvListsSheet extends StatelessWidget {
  const TvListsSheet({
    super.key,
    required this.show,
    required this.listsAsync,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.onCreateList,
    required this.onToggleList,
    required this.onDone,
  });

  final CatalogItem show;
  final AsyncValue<TvCustomListsData> listsAsync;
  final int? seasonNumber;
  final int? episodeNumber;
  final Future<void> Function() onCreateList;
  final Future<void> Function(TvCustomList list) onToggleList;
  final VoidCallback onDone;

  String get _scopeLabel {
    final item = TvCustomListItem(
      show: show,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    return switch (item.entryKind) {
      TvCustomListEntryKind.show => 'this series',
      TvCustomListEntryKind.season => 'Season $seasonNumber',
      TvCustomListEntryKind.episode =>
        'S${seasonNumber?.toString().padLeft(2, '0')}E${episodeNumber?.toString().padLeft(2, '0')}',
    };
  }

  TvCustomListItem _targetItem() {
    return TvCustomListItem(
      show: show,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
  }

  static String _listSubtitle(TvCustomList list) {
    final n = list.items.length;
    if (n == 0) {
      return 'Empty';
    }
    if (n == 1) {
      return '1 entry';
    }
    return '$n entries';
  }

  @override
  Widget build(BuildContext context) {
    final target = _targetItem();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: listsAsync.when(
        loading: () => const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => SizedBox(
          height: 180,
          child: ErrorState(error: error),
        ),
        data: (data) {
          final lists = data.lists;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Custom TV lists',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Each list can mix series, seasons, and episodes. Add $_scopeLabel to a list.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (lists.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('No lists yet. Create one below.'),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: lists.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final list = lists[index];
                      final contains = list.items.any((existing) => existing.matches(target));
                      return Card(
                        child: CheckboxListTile(
                          value: contains,
                          onChanged: (_) async {
                            await onToggleList(list);
                          },
                          title: Text(list.name),
                          subtitle: Text(_listSubtitle(list)),
                          controlAffinity: ListTileControlAffinity.trailing,
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await onCreateList();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Create list'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onDone,
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
