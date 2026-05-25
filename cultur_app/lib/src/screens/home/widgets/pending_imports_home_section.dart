import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/pending_imports_providers.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/games_tracking_shelf_section.dart';

/// Pending-import shelf on category home — hidden when the list is empty.
class PendingImportsHomeSection extends ConsumerWidget {
  const PendingImportsHomeSection({
    required this.username,
    required this.scope,
    required this.emptyMessage,
    required this.onSeeAll,
    super.key,
  });

  final String username;
  final LibraryMediaScope scope;
  final String emptyMessage;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      pendingImportsShelfProvider((username: username, scope: scope)),
    );

    final showSection = state.maybeWhen(
      data: (items) => items.isNotEmpty,
      orElse: () => false,
    );
    if (!showSection) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        GamesTrackingShelfSection(
          title: 'Pending imports',
          icon: Icons.link_off_outlined,
          state: state,
          emptyMessage: emptyMessage,
          onSeeAll: onSeeAll,
          badgeForItem: (_) => (icon: Icons.link_off_outlined, tooltip: 'Pending catalog match'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
