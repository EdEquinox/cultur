import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/library_search_focus_provider.dart';

/// Circular search control floating above [FloatingLibraryNav].
class FloatingSearchFab extends ConsumerWidget {
  const FloatingSearchFab({
    required this.mediaScope,
    super.key,
  });

  final LibraryMediaScope mediaScope;

  static const double size = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primaryContainer,
      elevation: 6,
      shadowColor: scheme.scrim.withValues(alpha: 0.45),
      shape: CircleBorder(
        side: BorderSide(
          color: scheme.scrim.withValues(alpha: 0.45),
          width: 0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => handleFloatingLibrarySearchTap(context, ref, mediaScope),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.search,
            size: 20,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
