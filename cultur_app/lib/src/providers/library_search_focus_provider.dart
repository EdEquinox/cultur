import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';

/// Tracks the active page search field so the floating FAB can focus it.
class LibrarySearchFocusRegistry extends Notifier<FocusNode?> {
  bool _pendingFocus = false;

  @override
  FocusNode? build() => null;

  void register(FocusNode node) {
    state = node;
    if (_pendingFocus) {
      _pendingFocus = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (state == node && node.canRequestFocus) {
          node.requestFocus();
        }
      });
    }
  }

  void unregister(FocusNode node) {
    if (state == node) {
      state = null;
    }
  }

  void clear() {
    _pendingFocus = false;
    state = null;
  }

  bool tryFocus() {
    final node = state;
    if (node == null || !node.canRequestFocus) {
      state = null;
      return false;
    }
    final nodeContext = node.context;
    if (nodeContext == null || !nodeContext.mounted) {
      state = null;
      return false;
    }
    node.requestFocus();
    return true;
  }

  void armFocusOnNextRegistration() {
    _pendingFocus = true;
  }
}

final librarySearchFocusRegistryProvider =
    NotifierProvider<LibrarySearchFocusRegistry, FocusNode?>(
  LibrarySearchFocusRegistry.new,
);

bool routeSupportsInlineLibrarySearch(String location) {
  final path = Uri.parse(location).path;
  if (path == '/') {
    return true;
  }
  if (path.startsWith('/category/')) {
    return true;
  }
  if (path.startsWith('/library/')) {
    return true;
  }
  return false;
}

void handleFloatingLibrarySearchTap(
  BuildContext context,
  WidgetRef ref,
  LibraryMediaScope mediaScope,
) {
  final location = GoRouterState.of(context).uri.toString();
  final registry = ref.read(librarySearchFocusRegistryProvider.notifier);
  final browsePath = mediaScope.catalogBrowsePath;

  // Only focus an inline field on the *current* screen (not one left on the stack).
  if (routeSupportsInlineLibrarySearch(location)) {
    if (registry.tryFocus()) {
      return;
    }
    registry.armFocusOnNextRegistration();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!registry.tryFocus() && context.mounted) {
        context.push(browsePath);
      }
    });
    return;
  }

  registry.clear();
  registry.armFocusOnNextRegistration();
  context.push(browsePath);
}
