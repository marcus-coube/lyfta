import 'package:flutter/material.dart';

import '../theme/ly_theme.dart';
import '../tokens/ly_colors.dart';
import '../tokens/ly_typography.dart';

/// Marca do DÜO.
///
/// - `wordmark: true` (padrão): letreiro "DÜO" com o Ü em verde-limão — o
///   trema é a assinatura da marca — e, com [tagline], "TRAINING" espaçado
///   embaixo.
/// - `wordmark: false`: o ícone do app — Ü escuro sobre quadrado verde-limão.
///
/// [size] é a altura do ícone e, no letreiro, a altura das maiúsculas.
/// O Ü é desenhado (não é o glifo da fonte) para manter os pontos quadrados
/// da identidade.
class LyLogo extends StatelessWidget {
  const LyLogo({
    super.key,
    this.size = 40,
    this.wordmark = true,
    this.tagline = false,
  });

  final double size;
  final bool wordmark;
  final bool tagline;

  @override
  Widget build(BuildContext context) {
    if (!wordmark) return LyAppIcon(size: size);

    final c = context.ly;
    // Manrope tem altura de maiúscula ~0,72 em: a fonte é dimensionada para
    // as maiúsculas medirem [size], igual ao Ü desenhado.
    final fontSize = size / 0.72;
    final letter = LyType.display(c.textPrimary).copyWith(
      fontSize: fontSize,
      height: 1,
      letterSpacing: 0,
    );

    final word = Semantics(
      label: 'DÜO',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('D', style: letter),
          SizedBox(width: size * 0.06),
          _UmlautU(capHeight: size, color: LyPalette.lime),
          SizedBox(width: size * 0.06),
          Text('O', style: letter),
        ],
      ),
    );

    if (!tagline) return word;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        word,
        SizedBox(height: size * 0.28),
        Text(
          'TRAINING',
          style: LyType.title(c.textPrimary).copyWith(
            fontSize: size * 0.26,
            fontWeight: FontWeight.w600,
            letterSpacing: size * 0.16,
          ),
        ),
      ],
    );
  }
}

/// Ícone do app: Ü escuro centrado num quadrado verde-limão arredondado.
class LyAppIcon extends StatelessWidget {
  const LyAppIcon({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'DÜO',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: LyPalette.lime,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        alignment: Alignment.center,
        child: _UmlautU(capHeight: size * 0.42, color: LyPalette.ink950),
      ),
    );
  }
}

/// O "Ü" da marca: U geométrico com dois pontos quadrados.
///
/// A baseline fica no pé do U, para alinhar com as letras de texto vizinhas.
class _UmlautU extends StatelessWidget {
  const _UmlautU({required this.capHeight, required this.color});

  final double capHeight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final g = _UGeometry(capHeight);
    return Baseline(
      baseline: g.height,
      baselineType: TextBaseline.alphabetic,
      child: CustomPaint(
        size: Size(g.width, g.height),
        painter: _UmlautUPainter(g, color),
      ),
    );
  }
}

class _UGeometry {
  _UGeometry(this.capHeight);

  final double capHeight;

  double get stroke => capHeight * 0.2;
  double get width => capHeight * 0.8;
  double get dot => stroke * 0.85;
  double get dotGap => capHeight * 0.1;

  /// Altura total: pontos + respiro + U.
  double get height => dot + dotGap + capHeight;
}

class _UmlautUPainter extends CustomPainter {
  _UmlautUPainter(this.g, this.color);

  final _UGeometry g;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final top = g.dot + g.dotGap;
    final s = g.stroke;
    final w = g.width;

    // Pontos quadrados, centrados sobre cada haste.
    for (final cx in [s / 2, w - s / 2]) {
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, g.dot / 2), width: g.dot, height: g.dot),
        paint,
      );
    }

    // U: duas hastes e a curva de baixo, como traço grosso de pontas retas.
    final r = (w - s) / 2;
    final centerY = top + g.capHeight - s / 2 - r;
    final path = Path()
      ..moveTo(s / 2, top)
      ..lineTo(s / 2, centerY)
      ..arcToPoint(
        Offset(w - s / 2, centerY),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..lineTo(w - s / 2, top);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(_UmlautUPainter old) => old.g.capHeight != g.capHeight || old.color != color;
}
