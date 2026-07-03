import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Escala tipográfica da Lyfta — família Manrope.
///
/// Displays/títulos usam pesos altos e tracking negativo (voz atlética);
/// corpo fica em 400/500 para leitura.
abstract final class LyType {
  static TextStyle _base(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle display(Color c) =>
      _base(32, FontWeight.w800, c, height: 1.15, letterSpacing: -0.8);

  static TextStyle h1(Color c) =>
      _base(24, FontWeight.w800, c, height: 1.2, letterSpacing: -0.5);

  static TextStyle h2(Color c) =>
      _base(20, FontWeight.w700, c, height: 1.25, letterSpacing: -0.3);

  static TextStyle title(Color c) =>
      _base(16, FontWeight.w700, c, height: 1.3);

  static TextStyle body(Color c) =>
      _base(15, FontWeight.w500, c, height: 1.5);

  static TextStyle bodySm(Color c) =>
      _base(13, FontWeight.w500, c, height: 1.45);

  static TextStyle label(Color c) =>
      _base(13, FontWeight.w700, c, height: 1.2, letterSpacing: 0.2);

  static TextStyle caption(Color c) =>
      _base(11, FontWeight.w600, c, height: 1.3, letterSpacing: 0.4);

  /// Números de destaque (cargas, séries, cronômetro) — tabular.
  static TextStyle numeric(Color c, {double size = 20}) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: FontWeight.w800,
      color: c,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      displaySmall: display(primary),
      headlineMedium: h1(primary),
      headlineSmall: h2(primary),
      titleMedium: title(primary),
      bodyMedium: body(primary),
      bodySmall: bodySm(secondary),
      labelLarge: label(primary),
      labelSmall: caption(secondary),
    );
  }
}
