import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/tokens/ly_colors.dart';

/// Razão de contraste WCAG 2.x (luminância relativa).
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// P8.3: todo token usado como texto no tema dark (o único que o app mostra)
/// tem de passar AA para texto normal (4,5:1) em cada fundo em que aparece.
void main() {
  const colors = LyColors.dark;
  final backgrounds = <String, Color>{
    'background': colors.background,
    'surface': colors.surface,
    'surfaceElevated': colors.surfaceElevated,
  };
  final texts = <String, Color>{
    'textPrimary': colors.textPrimary,
    'textSecondary': colors.textSecondary,
    'accent': colors.accent,
    'success': colors.success,
    'warning': colors.warning,
    'danger': colors.danger,
    'info': colors.info,
  };

  for (final bg in backgrounds.entries) {
    for (final fg in texts.entries) {
      test('dark: ${fg.key} sobre ${bg.key} >= 4,5:1', () {
        expect(contrast(fg.value, bg.value), greaterThanOrEqualTo(4.5));
      });
    }
  }

  test('dark: onAccent sobre accent >= 4,5:1', () {
    expect(contrast(colors.onAccent, colors.accent), greaterThanOrEqualTo(4.5));
  });
}
