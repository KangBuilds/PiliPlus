import 'package:PiliPlus/utils/bili_colors.dart';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart'
    show ThemeData, Color, ColorScheme, Brightness, Colors;

extension ThemeDataExt on ThemeData {
  bool get isLight => brightness.isLight;

  bool get isDark => brightness.isDark;
}

extension ColorSchemeExt on ColorScheme {
  Color get vipColor =>
      brightness.isLight ? BiliColors.pinkLight : BiliColors.pinkDark;

  Color get blue =>
      brightness.isLight ? BiliColors.blueLight : BiliColors.blueDark;

  Color get btnColor =>
      brightness.isLight ? BiliColors.pinkLight : const Color(0xFF8F0030);

  Color get freeColor =>
      brightness.isLight ? const Color(0xFFFF7F24) : const Color(0xFFD66011);

  bool get isLight => brightness.isLight;

  bool get isDark => brightness.isDark;
}

extension ColorExtension on Color {
  Color darken([double amount = .5]) {
    assert(amount >= 0 && amount <= 1, 'Amount must be between 0 and 1');
    return Color.lerp(this, Colors.black, amount)!;
  }

  ColorScheme asColorSchemeSeed([
    FlexSchemeVariant variant = .material,
    Brightness brightness = .light,
  ]) {
    final scheme = SeedColorScheme.fromSeeds(
      primaryKey: this,
      variant: variant,
      brightness: brightness,
      useExpressiveOnContainerColors: false,
    );
    // FlexSeedScheme supplies Material UI colors; the app uses Flutter's theme.
    return ColorScheme(
      brightness: scheme.brightness,
      primary: scheme.primary,
      onPrimary: scheme.onPrimary,
      primaryContainer: scheme.primaryContainer,
      onPrimaryContainer: scheme.onPrimaryContainer,
      primaryFixed: scheme.primaryFixed,
      primaryFixedDim: scheme.primaryFixedDim,
      onPrimaryFixed: scheme.onPrimaryFixed,
      onPrimaryFixedVariant: scheme.onPrimaryFixedVariant,
      secondary: scheme.secondary,
      onSecondary: scheme.onSecondary,
      secondaryContainer: scheme.secondaryContainer,
      onSecondaryContainer: scheme.onSecondaryContainer,
      secondaryFixed: scheme.secondaryFixed,
      secondaryFixedDim: scheme.secondaryFixedDim,
      onSecondaryFixed: scheme.onSecondaryFixed,
      onSecondaryFixedVariant: scheme.onSecondaryFixedVariant,
      tertiary: scheme.tertiary,
      onTertiary: scheme.onTertiary,
      tertiaryContainer: scheme.tertiaryContainer,
      onTertiaryContainer: scheme.onTertiaryContainer,
      tertiaryFixed: scheme.tertiaryFixed,
      tertiaryFixedDim: scheme.tertiaryFixedDim,
      onTertiaryFixed: scheme.onTertiaryFixed,
      onTertiaryFixedVariant: scheme.onTertiaryFixedVariant,
      error: scheme.error,
      onError: scheme.onError,
      errorContainer: scheme.errorContainer,
      onErrorContainer: scheme.onErrorContainer,
      surface: scheme.surface,
      onSurface: scheme.onSurface,
      surfaceDim: scheme.surfaceDim,
      surfaceBright: scheme.surfaceBright,
      surfaceContainerLowest: scheme.surfaceContainerLowest,
      surfaceContainerLow: scheme.surfaceContainerLow,
      surfaceContainer: scheme.surfaceContainer,
      surfaceContainerHigh: scheme.surfaceContainerHigh,
      surfaceContainerHighest: scheme.surfaceContainerHighest,
      onSurfaceVariant: scheme.onSurfaceVariant,
      outline: scheme.outline,
      outlineVariant: scheme.outlineVariant,
      shadow: scheme.shadow,
      scrim: scheme.scrim,
      inverseSurface: scheme.inverseSurface,
      onInverseSurface: scheme.onInverseSurface,
      inversePrimary: scheme.inversePrimary,
      surfaceTint: scheme.surfaceTint,
    );
  }
}

extension BrightnessExt on Brightness {
  Brightness get reverse => isLight ? Brightness.dark : Brightness.light;

  bool get isLight => this == Brightness.light;

  bool get isDark => this == Brightness.dark;
}
