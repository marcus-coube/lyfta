import 'package:flutter/material.dart';

import '../theme/ly_theme.dart';
import '../tokens/ly_colors.dart';
import '../tokens/ly_typography.dart';

/// Marca da Lyfta: símbolo (anilha estilizada em lime) + wordmark.
class LyLogo extends StatelessWidget {
  const LyLogo({super.key, this.size = 40, this.wordmark = true});

  final double size;
  final bool wordmark;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    final glyph = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: LyPalette.lime,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Center(
        // Barra + anilhas: leitura de "halter" em 3 traços.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _plate(size * 0.14, size * 0.46),
            SizedBox(width: size * 0.07),
            _plate(size * 0.14, size * 0.28),
            SizedBox(width: size * 0.07),
            _plate(size * 0.14, size * 0.46),
          ],
        ),
      ),
    );

    if (!wordmark) return glyph;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        SizedBox(width: size * 0.35),
        Text(
          'lyfta',
          style: LyType.display(c.textPrimary).copyWith(
            fontSize: size * 0.72,
            letterSpacing: -1.2,
          ),
        ),
      ],
    );
  }

  Widget _plate(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: LyPalette.ink950,
        borderRadius: BorderRadius.circular(width / 2),
      ),
    );
  }
}
