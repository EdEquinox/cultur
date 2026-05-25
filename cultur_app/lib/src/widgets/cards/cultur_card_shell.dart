import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';

/// Tappable surface for list-style cards (Material [Card] + [InkWell]).
class CulturCardShell extends StatelessWidget {
  const CulturCardShell({
    required this.child,
    super.key,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(12),
    this.useCard = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final bool useCard;

  @override
  Widget build(BuildContext context) {
    final tokens = context.culturTokens;
    final ink = InkWell(
      borderRadius: tokens.borderRadiusTight,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(padding: padding, child: child),
    );

    if (!useCard) {
      return ink;
    }
    return Card(child: ink);
  }
}
