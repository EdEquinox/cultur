import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Design tokens reachable from any build context.
///
/// Usage: `Theme.of(context).extension<CulturTokens>()!.radiusTight`
/// or [BuildContext.culturTokens] from this file.
@immutable
class CulturTokens extends ThemeExtension<CulturTokens> {
  const CulturTokens({
    this.radiusTight = 4,
    this.radiusSheetTop = 16,
    this.radiusDialog = 16,
    this.shelfRowBackground = const Color(0xFF1B1B1B),
    this.shelfRowBackgroundElevated = const Color(0xFF2A2A2A),
  });

  /// Cards, chips, text fields — sharp, dense UI.
  final double radiusTight;

  /// Bottom sheets, large surfaces.
  final double radiusSheetTop;

  /// Dialogs, full-screen modals corners.
  final double radiusDialog;

  /// Horizontal media shelves / dense rows (legacy hardcoded `0xFF1B1B1B`).
  final Color shelfRowBackground;

  /// Slightly lifted shelf panels (`0xFF2A2A2A`).
  final Color shelfRowBackgroundElevated;

  BorderRadius get borderRadiusTight => BorderRadius.circular(radiusTight);

  BorderRadius get borderRadiusSheetTop =>
      BorderRadius.vertical(top: Radius.circular(radiusSheetTop));

  BorderRadius get borderRadiusDialog => BorderRadius.circular(radiusDialog);

  static CulturTokens of(BuildContext context) {
    final t = Theme.of(context).extension<CulturTokens>();
    assert(t != null, 'ThemeData.extensions must include CulturTokens');
    return t!;
  }

  @override
  CulturTokens copyWith({
    double? radiusTight,
    double? radiusSheetTop,
    double? radiusDialog,
    Color? shelfRowBackground,
    Color? shelfRowBackgroundElevated,
  }) {
    return CulturTokens(
      radiusTight: radiusTight ?? this.radiusTight,
      radiusSheetTop: radiusSheetTop ?? this.radiusSheetTop,
      radiusDialog: radiusDialog ?? this.radiusDialog,
      shelfRowBackground: shelfRowBackground ?? this.shelfRowBackground,
      shelfRowBackgroundElevated:
          shelfRowBackgroundElevated ?? this.shelfRowBackgroundElevated,
    );
  }

  @override
  CulturTokens lerp(ThemeExtension<CulturTokens>? other, double t) {
    if (other is! CulturTokens) {
      return this;
    }
    return CulturTokens(
      radiusTight: lerpDouble(radiusTight, other.radiusTight, t)!,
      radiusSheetTop: lerpDouble(radiusSheetTop, other.radiusSheetTop, t)!,
      radiusDialog: lerpDouble(radiusDialog, other.radiusDialog, t)!,
      shelfRowBackground: Color.lerp(
        shelfRowBackground,
        other.shelfRowBackground,
        t,
      )!,
      shelfRowBackgroundElevated: Color.lerp(
        shelfRowBackgroundElevated,
        other.shelfRowBackgroundElevated,
        t,
      )!,
    );
  }
}

extension CulturThemeContext on BuildContext {
  CulturTokens get culturTokens => CulturTokens.of(this);
}

/// Single source of truth for brand colours and neutrals (dark theme).
abstract final class CulturPalette {
  CulturPalette._();

  /// Default accent (rose) — overridden by [buildAppTheme].
  static const Color brand = Color(0xFF8B5C69);

  static const Color scaffold = Color(0xFF121212);
  static const Color surface = Color(0xFF171717);
  static const Color surfaceContainerLow = Color(0xFF161616);
  static const Color surfaceContainer = Color(0xFF1F1F1F);
  static const Color surfaceContainerHigh = Color(0xFF272727);
  static const Color surfaceContainerHighest = Color(0xFF313131);

  static const Color onSurface = Color(0xFFF2F1F1);
  static const Color onSurfaceVariant = Color(0xFFB6B0B2);
  static const Color hint = Color(0xFF9D989A);

  static const Color navBar = Color(0xFF161616);
  static const Color chipBackground = Color(0xFF262626);
  static const Color inputFill = Color(0xFF212121);

  static const Color shelfRow = Color(0xFF1B1B1B);
  static const Color shelfRowElevated = Color(0xFF2A2A2A);
}

ThemeData buildAppTheme({Color accentSeed = CulturPalette.brand}) {
  const tokens = CulturTokens(
    radiusTight: 4,
    radiusSheetTop: 16,
    radiusDialog: 16,
    shelfRowBackground: CulturPalette.shelfRow,
    shelfRowBackgroundElevated: CulturPalette.shelfRowElevated,
  );

  final generated = ColorScheme.fromSeed(
    seedColor: accentSeed,
    brightness: Brightness.dark,
  );

  final colorScheme = generated.copyWith(
    primary: generated.primary,
    onPrimary: generated.onPrimary,
    primaryContainer: generated.primaryContainer,
    onPrimaryContainer: generated.onPrimaryContainer,
    surface: CulturPalette.surface,
    surfaceContainerLow: CulturPalette.surfaceContainerLow,
    surfaceContainer: CulturPalette.surfaceContainer,
    surfaceContainerHigh: CulturPalette.surfaceContainerHigh,
    surfaceContainerHighest: CulturPalette.surfaceContainerHighest,
    onSurface: CulturPalette.onSurface,
    onSurfaceVariant: CulturPalette.onSurfaceVariant,
    scrim: Colors.black,
    shadow: Colors.black,
  );

  final tightShape = RoundedRectangleBorder(
    borderRadius: tokens.borderRadiusTight,
  );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: CulturPalette.scaffold,
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    extensions: const [tokens],
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      iconTheme: IconThemeData(color: colorScheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: CulturPalette.navBar,
      indicatorColor: colorScheme.primary,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? colorScheme.onPrimary : CulturPalette.onSurfaceVariant,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? colorScheme.onPrimary : CulturPalette.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: CulturPalette.surfaceContainer,
      shape: tightShape,
      margin: EdgeInsets.zero,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: CulturPalette.chipBackground,
      selectedColor: colorScheme.primary,
      disabledColor: CulturPalette.chipBackground,
      side: BorderSide.none,
      shape: tightShape,
      labelStyle: TextStyle(color: colorScheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CulturPalette.inputFill,
      hintStyle: TextStyle(color: CulturPalette.hint),
      labelStyle: TextStyle(color: CulturPalette.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: tokens.borderRadiusTight,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: tokens.borderRadiusTight,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: tokens.borderRadiusTight,
        borderSide: BorderSide(color: colorScheme.primary),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: tokens.borderRadiusSheetTop,
      ),
      dragHandleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: tokens.borderRadiusDialog,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(color: colorScheme.onSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSheetTop),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.onSurfaceVariant,
      textColor: colorScheme.onSurface,
      tileColor: Colors.transparent,
    ),
    iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSheetTop * 0.75),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: tokens.borderRadiusTight,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: tokens.borderRadiusTight,
        ),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: tokens.borderRadiusTight,
        ),
      ),
    ),
  );
}
