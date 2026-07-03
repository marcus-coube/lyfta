import 'package:flutter/material.dart';

/// Paleta bruta da marca Lyfta.
///
/// Nunca use estas constantes direto em widgets de feature — consuma via
/// [LyTheme]/`context.ly`, que resolve o token certo para o tema ativo.
abstract final class LyPalette {
  // Marca
  static const Color lime = Color(0xFFC8F135); // Lyfta Lime — única cor de destaque
  static const Color limeBright = Color(0xFFD9FF4B);
  static const Color limeDim = Color(0xFF9DBF23);

  // Escala de grafite (dark-first)
  static const Color ink950 = Color(0xFF07090C);
  static const Color ink900 = Color(0xFF0B0E12); // fundo dark
  static const Color ink800 = Color(0xFF12161C); // superfície dark
  static const Color ink700 = Color(0xFF1A2028); // superfície elevada dark
  static const Color ink600 = Color(0xFF242C36); // bordas dark
  static const Color ink500 = Color(0xFF3A4450);

  // Neutros claros
  static const Color gray400 = Color(0xFF9AA5B1); // texto secundário dark
  static const Color gray200 = Color(0xFFD7DDE3);
  static const Color gray100 = Color(0xFFE8ECF1); // texto primário dark
  static const Color gray50 = Color(0xFFF6F8FA); // fundo light
  static const Color white = Color(0xFFFFFFFF);

  // Semânticas
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);
  static const Color info = Color(0xFF60A5FA);
}

/// Tokens de cor resolvidos por tema. Componentes e telas leem daqui.
@immutable
class LyColors extends ThemeExtension<LyColors> {
  const LyColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  static const LyColors dark = LyColors(
    background: LyPalette.ink900,
    surface: LyPalette.ink800,
    surfaceElevated: LyPalette.ink700,
    border: LyPalette.ink600,
    textPrimary: LyPalette.gray100,
    textSecondary: LyPalette.gray400,
    accent: LyPalette.lime,
    onAccent: LyPalette.ink950,
    success: LyPalette.success,
    warning: LyPalette.warning,
    danger: LyPalette.danger,
    info: LyPalette.info,
  );

  static const LyColors light = LyColors(
    background: LyPalette.gray50,
    surface: LyPalette.white,
    surfaceElevated: LyPalette.white,
    border: LyPalette.gray200,
    textPrimary: LyPalette.ink800,
    textSecondary: LyPalette.ink500,
    accent: LyPalette.limeDim,
    onAccent: LyPalette.ink950,
    success: LyPalette.success,
    warning: LyPalette.warning,
    danger: LyPalette.danger,
    info: LyPalette.info,
  );

  @override
  LyColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
  }) {
    return LyColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
    );
  }

  @override
  LyColors lerp(ThemeExtension<LyColors>? other, double t) {
    if (other is! LyColors) return this;
    return LyColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}
