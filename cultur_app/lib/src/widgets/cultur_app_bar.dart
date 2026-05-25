import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';

/// App-wide top bar: back (when available), brand or logo mark, profile shortcut.
class CulturAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CulturAppBar({
    super.key,
    this.additionalActions = const [],
    this.showProfileAction = true,
    this.backEnabled = true,
    this.onBack,
    this.onLogoTap,
  });

  final List<Widget> additionalActions;
  final bool showProfileAction;
  final bool backEnabled;
  final VoidCallback? onBack;
  final VoidCallback? onLogoTap;

  static const double _sideSlotWidth = 48;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  VoidCallback _resolveLogoTap(BuildContext context) {
    return onLogoTap ??
        () {
          final state = GoRouterState.of(context);
          final scope = libraryMediaScopeFromRoute(state.uri);
          if (!libraryIsOnCatalogHome(state, scope)) {
            context.go(scope.catalogHomePath);
          }
        };
  }

  List<Widget> _trailingActions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      ...additionalActions,
      if (showProfileAction)
        IconButton(
          tooltip: 'Profile',
          onPressed: () => context.push('/profile'),
          icon: Icon(Icons.person_outline, color: scheme.onSurface),
        )
      else
        const SizedBox(width: _sideSlotWidth),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    final scheme = Theme.of(context).colorScheme;
    final logoTap = _resolveLogoTap(context);

    if (!canPop) {
      return AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 16,
        title: CulturBrandTitle(onTap: logoTap),
        actions: _trailingActions(context),
      );
    }

    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: true,
      leading: IconButton(
        tooltip: 'Back',
        onPressed: backEnabled ? (onBack ?? () => context.pop()) : null,
        icon: Icon(Icons.arrow_back, color: scheme.onSurface),
      ),
      leadingWidth: _sideSlotWidth,
      title: CulturLogoMark(onTap: logoTap),
      actions: _trailingActions(context),
    );
  }
}

/// Root layout: brand mark + app name on the left.
class CulturBrandTitle extends StatelessWidget {
  const CulturBrandTitle({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.culturTokens;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CulturLogoMark(showIcon: false),
        const SizedBox(width: 10),
        Text(
          'cult.u.r',
          style: theme.textTheme.titleLarge?.copyWith(
            color: CulturPalette.onSurface,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.15,
            height: 1,
          ),
        ),
      ],
    );

    if (onTap == null) {
      return content;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusTight),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: content,
      ),
    );
  }
}

/// Placeholder app logo until brand assets are ready.
class CulturLogoMark extends StatelessWidget {
  const CulturLogoMark({
    super.key,
    this.onTap,
    this.showIcon = true,
  });

  final VoidCallback? onTap;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.culturTokens;

    final scheme = Theme.of(context).colorScheme;
    final mark = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(tokens.radiusTight + 2),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.88),
          width: 1,
        ),
      ),
      child: SizedBox(
        width: 28,
        height: 28,
        child: showIcon
            ? Icon(
                Icons.grid_view_rounded,
                size: 16,
                color: scheme.onPrimary.withValues(alpha: 0.9),
              )
            : null,
      ),
    );

    if (onTap == null) {
      return mark;
    }

    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      tooltip: 'Home',
      onPressed: onTap,
      icon: mark,
    );
  }
}
