import 'package:flutter/material.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/models/games/game_company_link.dart';
import 'package:yamtrack/src/screens/widgets/game_company_chip.dart';

/// Room for the corner [N+] badge without shifting chip alignment between columns.
const EdgeInsets _badgeOuterInset = EdgeInsets.only(top: 6, right: 6);

/// One developer or publisher column; extra entries hide behind a corner `N+` badge.
class GameCompanyGroup extends StatefulWidget {
  const GameCompanyGroup({
    super.key,
    required this.companies,
    required this.icon,
    required this.onOpenCompany,
  });

  final List<GameCompanyLink> companies;
  final IconData icon;
  final ValueChanged<GameCompanyLink> onOpenCompany;

  @override
  State<GameCompanyGroup> createState() => _GameCompanyGroupState();
}

class _GameCompanyGroupState extends State<GameCompanyGroup> {
  final _layerLink = LayerLink();
  final _portalController = OverlayPortalController();
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _portalController.show();
      } else {
        _portalController.hide();
      }
    });
  }

  void _close() {
    if (!_expanded) {
      return;
    }
    setState(() {
      _expanded = false;
      _portalController.hide();
    });
  }

  Widget _primaryChip(GameCompanyLink company) {
    return GameCompanyChip(
      name: company.name,
      icon: widget.icon,
      expanded: true,
      onTap: () => widget.onOpenCompany(company),
    );
  }

  Widget _chipAnchor({required GameCompanyLink company, Widget? badge}) {
    return _CompanyChipAnchor(
      chip: _primaryChip(company),
      badge: badge,
    );
  }

  @override
  Widget build(BuildContext context) {
    final companies = widget.companies.where((c) => c.isValid).toList();
    if (companies.isEmpty) {
      return const SizedBox.shrink();
    }

    if (companies.length == 1) {
      return _chipAnchor(company: companies.first);
    }

    final extraCount = companies.length - 1;

    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (context) {
        final panelWidth = _layerLink.leaderSize?.width;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _close,
                behavior: HitTestBehavior.translucent,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 4),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(6),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: panelWidth,
                  child: _CompanyOverflowPanel(
                    companies: companies.skip(1).toList(),
                    icon: widget.icon,
                    onOpenCompany: (company) {
                      _close();
                      widget.onOpenCompany(company);
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: _chipAnchor(
          company: companies.first,
          badge: _CompanyCountBadge(
            count: extraCount,
            expanded: _expanded,
            onTap: _toggleExpanded,
          ),
        ),
      ),
    );
  }
}

/// Shared slot so developer / publisher chips share the same box and badge offset.
class _CompanyChipAnchor extends StatelessWidget {
  const _CompanyChipAnchor({
    required this.chip,
    this.badge,
  });

  final Widget chip;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _badgeOuterInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(width: double.infinity, child: chip),
          if (badge != null)
            Positioned(
              top: -6,
              right: -6,
              child: badge!,
            ),
        ],
      ),
    );
  }
}

class _CompanyCountBadge extends StatelessWidget {
  const _CompanyCountBadge({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      elevation: expanded ? 4 : 2,
      shadowColor: scheme.scrim.withValues(alpha: 0.35),
      color: expanded ? scheme.primary : scheme.primaryContainer,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Text(
              '$count+',
              style: CulturCatalogTypography.gridSubtitle(theme, scheme).copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 10,
                height: 1,
                color: expanded ? scheme.onPrimary : scheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanyOverflowPanel extends StatelessWidget {
  const _CompanyOverflowPanel({
    required this.companies,
    required this.icon,
    required this.onOpenCompany,
  });

  final List<GameCompanyLink> companies;
  final IconData icon;
  final ValueChanged<GameCompanyLink> onOpenCompany;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < companies.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            InkWell(
              onTap: () => onOpenCompany(companies[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        companies[i].name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: CulturCatalogTypography.gridTitle(theme),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
