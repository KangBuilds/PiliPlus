import 'dart:ui';

import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves generated tones in the Flutter theme', () {
    const seed = Color(0xFFCA3168);
    final generated = SeedColorScheme.fromSeeds(
      primaryKey: seed,
      variant: .chroma,
      brightness: .dark,
      useExpressiveOnContainerColors: false,
    );
    final theme = seed.asColorSchemeSeed(.chroma, .dark);

    expect(theme.brightness, Brightness.dark);
    expect(theme.primary, generated.primary);
    expect(theme.onTertiaryFixed, generated.onTertiaryFixed);
    expect(theme.surfaceContainerHighest, generated.surfaceContainerHighest);
    expect(theme.surfaceTint, generated.surfaceTint);
  });
}
