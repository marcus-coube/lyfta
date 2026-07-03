import 'package:flutter/material.dart';

import 'ly_colors.dart';

/// Sombras. No tema dark a elevação vem mais de cor de superfície do que
/// de sombra — use [low] com parcimônia.
abstract final class LyElevation {
  static const List<BoxShadow> none = [];

  static const List<BoxShadow> low = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> medium = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  /// Brilho da marca para o CTA principal (dark).
  static List<BoxShadow> accentGlow = [
    BoxShadow(
      color: LyPalette.lime.withValues(alpha: 0.25),
      blurRadius: 32,
      offset: const Offset(0, 6),
    ),
  ];
}
