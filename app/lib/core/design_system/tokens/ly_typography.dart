import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Escala tipográfica do DÜO.
///
/// Manrope 800 nos títulos (tracking negativo, voz atlética) e 400 no texto;
/// JetBrains Mono nos rótulos pequenos ([caption], [mono]): chips, legendas e
/// metadados como "Anterior: 40 kg".
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
      _base(20, FontWeight.w800, c, height: 1.25, letterSpacing: -0.3);

  static TextStyle title(Color c) =>
      _base(16, FontWeight.w700, c, height: 1.3);

  static TextStyle body(Color c) =>
      _base(15, FontWeight.w400, c, height: 1.5);

  static TextStyle bodySm(Color c) =>
      _base(13, FontWeight.w400, c, height: 1.45);

  static TextStyle label(Color c) =>
      _base(13, FontWeight.w700, c, height: 1.2, letterSpacing: 0.2);

  /// Rótulo pequeno em JetBrains Mono (legendas, chips, metadados).
  static TextStyle caption(Color c) => mono(c);

  /// JetBrains Mono — a voz "técnica" da marca nos rótulos pequenos.
  static TextStyle mono(Color c, {double size = 11, FontWeight weight = FontWeight.w500}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: c,
      height: 1.3,
      letterSpacing: 0.2,
    );
  }

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
