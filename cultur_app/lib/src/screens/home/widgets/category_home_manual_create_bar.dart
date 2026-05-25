import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/pending_imports_providers.dart';
import 'package:yamtrack/src/utils/library_utils.dart';

/// Bottom action on category home tabs to add a manual library entry.
class CategoryHomeManualCreateBar extends ConsumerStatefulWidget {
  const CategoryHomeManualCreateBar({
    required this.scope,
    required this.username,
    super.key,
  });

  final LibraryMediaScope scope;
  final String username;

  @override
  ConsumerState<CategoryHomeManualCreateBar> createState() =>
      _CategoryHomeManualCreateBarState();
}

class _CategoryHomeManualCreateBarState extends ConsumerState<CategoryHomeManualCreateBar> {
  bool _isCreating = false;

  String get _mediaType => widget.scope.trackingApiMediaType;

  String get _label => switch (widget.scope) {
        LibraryMediaScope.movie => 'movie',
        LibraryMediaScope.tv => 'series',
        LibraryMediaScope.game => 'game',
        LibraryMediaScope.book => 'book',
        LibraryMediaScope.boardgame => 'board game',
        LibraryMediaScope.music => 'album',
      };

  Future<void> _openDialog() async {
    if (widget.username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to add items to your library.')),
      );
      return;
    }
    final titleController = TextEditingController();
    final subtitleController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Add $_label manually'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Use this when the title is not in any catalog. '
                  'You can link it later from the item page.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '${_label[0].toUpperCase()}${_label.substring(1)} title',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: subtitleController,
                  decoration: const InputDecoration(
                    labelText: 'Subtitle (optional)',
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.pop(dialogContext, true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add to library'),
            ),
          ],
        );
      },
    );
    final title = titleController.text.trim();
    final subtitle = subtitleController.text.trim();
    scheduleTextEditingControllerDispose(titleController);
    scheduleTextEditingControllerDispose(subtitleController);
    if (created != true || title.isEmpty || !mounted) {
      return;
    }
    setState(() => _isCreating = true);
    try {
      final client = ref.read(apiClientProvider);
      final out = await client.postJson(
        '/backend/library/manual-item',
        data: {
          'username': widget.username,
          'mediaType': _mediaType,
          'title': title,
          if (subtitle.isNotEmpty) 'subtitle': subtitle,
        },
      );
      final mediaId = out['mediaId']?.toString();
      if (!mounted) {
        return;
      }
      if (mediaId == null || mediaId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create item — missing id.')),
        );
        return;
      }
      ref.invalidate(libraryTrackingForScopeProvider(widget.scope));
      ref.invalidate(
        pendingImportsShelfProvider((username: widget.username, scope: widget.scope)),
      );
      final path = switch (widget.scope) {
        LibraryMediaScope.movie => '/movies/$mediaId',
        LibraryMediaScope.tv => '/tv/$mediaId',
        LibraryMediaScope.game => '/games/$mediaId',
        LibraryMediaScope.book => '/books/$mediaId',
        LibraryMediaScope.boardgame => '/boardgames/$mediaId',
        LibraryMediaScope.music => '/albums/$mediaId',
      };
      context.push(path);
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error, prefix: 'Could not add item:');
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: OutlinedButton.icon(
        onPressed: _isCreating ? null : _openDialog,
        icon: _isCreating
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : const Icon(Icons.add_circle_outline, size: 20),
        label: Text('Add $_label manually'),
      ),
    );
  }
}
