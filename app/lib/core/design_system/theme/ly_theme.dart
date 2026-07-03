import 'package:flutter/material.dart';

import '../tokens/ly_colors.dart';
import '../tokens/ly_radius.dart';
import '../tokens/ly_typography.dart';

/// Monta o [ThemeData] a partir dos tokens. Toda tela consome tokens via
/// `context.ly` (cores) e `Theme.of(context).textTheme` (tipografia).
abstract final class LyTheme {
  static ThemeData dark() => _build(LyColors.dark, Brightness.dark);

  static ThemeData light() => _build(LyColors.light, Brightness.light);

  static ThemeData _build(LyColors c, Brightness brightness) {
    final textTheme = LyType.textTheme(c.textPrimary, c.textSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.background,
      textTheme: textTheme,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: c.onAccent,
        secondary: c.surfaceElevated,
        onSecondary: c.textPrimary,
        error: c.danger,
        onError: c.onAccent,
        surface: c.surface,
        onSurface: c.textPrimary,
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: LyType.body(c.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: LyRadius.md,
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: LyRadius.md,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: LyRadius.md,
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: LyRadius.md,
          borderSide: BorderSide(color: c.danger),
        ),
      ),
      extensions: [c],
    );
  }
}

/// Açúcar para acessar os tokens de cor do tema ativo: `context.ly.accent`.
extension LyContext on BuildContext {
  LyColors get ly => Theme.of(this).extension<LyColors>()!;
}
