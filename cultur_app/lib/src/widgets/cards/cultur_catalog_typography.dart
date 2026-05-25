import 'package:flutter/material.dart';

/// Typography shared by [CulturCatalogGridCard], [CulturCatalogListRow], and detail pages.
abstract final class CulturCatalogTypography {
  static const double gridTitleFontSize = 11;
  static const double gridSubtitleFontSize = 9;

  /// Grid card primary line (title under poster).
  static TextStyle gridTitle(ThemeData theme) {
    return theme.textTheme.labelLarge!.copyWith(
      fontSize: gridTitleFontSize,
      fontWeight: FontWeight.w600,
      height: 1.15,
    );
  }

  /// Grid card secondary line (year · rating, etc.).
  static TextStyle gridSubtitle(ThemeData theme, ColorScheme scheme) {
    return theme.textTheme.labelSmall!.copyWith(
      color: scheme.onSurfaceVariant,
      fontSize: gridSubtitleFontSize,
      height: 1.1,
    );
  }

  /// List row primary line.
  static TextStyle listTitle(ThemeData theme) {
    return theme.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w600);
  }

  static TextStyle listTitleBig(ThemeData theme) {
    return theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w600);
  }

  /// List row meta line (roles, type, year segments).
  static TextStyle listMeta(
    ThemeData theme,
    ColorScheme scheme, {
    Color? color,
    FontWeight? fontWeight,
  }) {
    return theme.textTheme.bodySmall!.copyWith(
      color: color ?? scheme.onSurfaceVariant,
      fontWeight: fontWeight,
    );
  }

  /// Profile / entity name in detail headers.
  static TextStyle profileTitle(ThemeData theme) => listTitle(theme);

  /// Role, department, or subtitle under a profile name.
  static TextStyle profileSubtitle(ThemeData theme, ColorScheme scheme) =>
      listMeta(theme, scheme);

  /// Section headings (`Popular titles`, tab-adjacent labels).
  static TextStyle sectionHeading(ThemeData theme) => listTitle(theme);

  /// Biography / description body copy.
  static TextStyle bodyText(ThemeData theme, ColorScheme scheme) {
    return listMeta(theme, scheme).copyWith(height: 1.45);
  }

  /// `View more` and similar inline actions.
  static TextStyle linkAction(ThemeData theme, ColorScheme scheme) {
    return listMeta(theme, scheme).copyWith(
      color: scheme.primary.withValues(alpha: 0.75),
    );
  }

  /// Centered section titles (`Links`, `More details`).
  static TextStyle mutedSectionTitle(ThemeData theme, ColorScheme scheme) {
    return listMeta(
      theme,
      scheme,
      color: scheme.onSurface.withValues(alpha: 0.65),
      fontWeight: FontWeight.w500,
    );
  }

  /// Fact label (`Gender`, `Birthday`).
  static TextStyle factLabel(ThemeData theme, ColorScheme scheme) =>
      listMeta(theme, scheme);

  /// Fact value.
  static TextStyle factValue(ThemeData theme) => listTitle(theme);

  /// Numeric badge in watched/played buttons.
  static TextStyle actionCount(ThemeData theme) => listTitle(theme);

  /// `watched` / `played` label beside the count.
  static TextStyle actionLabel(ThemeData theme, ColorScheme scheme) {
    return gridTitle(theme).copyWith(
      color: scheme.onSurface.withValues(alpha: 0.85),
      fontWeight: FontWeight.w500,
    );
  }

  /// Empty states and helper copy.
  static TextStyle emptyState(ThemeData theme, ColorScheme scheme) =>
      listMeta(theme, scheme);

  /// Year group headers in catalog / filmography lists.
  static TextStyle yearDivider(ThemeData theme, ColorScheme scheme) =>
      listMeta(theme, scheme);
}
