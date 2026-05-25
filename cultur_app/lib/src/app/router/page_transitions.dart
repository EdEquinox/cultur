/// Shared [CustomTransitionPage] builders for stack navigation.
///
/// Used by route `pageBuilder`s so transitions stay consistent app-wide.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Builds a [CustomTransitionPage] with fade plus a slight horizontal slide.
///
/// [state] supplies [CustomTransitionPage.key] via [GoRouterState.pageKey].
/// [child] is the screen widget for this route.
CustomTransitionPage<void> buildAppRouteTransitionPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0.05, 0),
        end: Offset.zero,
      ).animate(curved);

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: slide,
          child: child,
        ),
      );
    },
  );
}
