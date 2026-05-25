import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/models/lists/custom_movie_lists_data.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/utils/library_utils.dart';

class GameListsSheet extends StatelessWidget {
  const GameListsSheet({
    super.key,
    required this.detail,
    required this.listsAsync,
    required this.onCreateList,
    required this.onToggleList,
    required this.onDone,
    this.isBuiltInList = BuiltInGameLists.isBuiltIn,
    this.itemLabel = 'games',
  });

  final CatalogDetail detail;
  final AsyncValue<CustomMovieListsData> listsAsync;
  final Future<void> Function() onCreateList;
  final Future<void> Function(CustomMovieList list) onToggleList;
  final VoidCallback onDone;
  final bool Function(String listId) isBuiltInList;
  final String itemLabel;

  @override
  Widget build(BuildContext context) {
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
          final lists = data.lists.where((l) => !isBuiltInList(l.id)).toList();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Custom lists',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Add this title to one or more personal lists.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (lists.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('No lists yet. Create your first one below.'),
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
                      final contains = list.items.any(
                        (item) => item.id == detail.media.id,
                      );
                      return Card(
                        child: CheckboxListTile(
                          value: contains,
                          onChanged: (_) async {
                            await onToggleList(list);
                          },
                          title: Text(list.name),
                          subtitle: Text('${list.items.length} $itemLabel'),
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
