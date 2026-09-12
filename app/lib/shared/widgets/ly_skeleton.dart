import 'package:flutter/widgets.dart';

import '../../core/design_system/design_system.dart';

/// Placeholder pulsante para conteúdo que ainda está carregando da rede
/// (P4.2 §2) — substitui o `CircularProgressIndicator` cru nas telas Hoje,
/// Evolução e Chat: a silhueta do que vai aparecer já ocupa o espaço certo,
/// então a tela não "pula" de vazio para cheia quando os dados chegam.
///
/// Widget "burro", igual `ExerciseMedia` (shared, não feature): telas
/// montam a forma (linhas, blocos) compondo esta peça — não há um
/// "skeleton de tela" genérico porque cada tela tem uma silhueta diferente.
class LySkeletonBox extends StatefulWidget {
  const LySkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius,
  });

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  State<LySkeletonBox> createState() => _LySkeletonBoxState();
}

class _LySkeletonBoxState extends State<LySkeletonBox>
    with SingleTickerProviderStateMixin {
  // Cadência de "respiração" do placeholder — não é uma transição de UI
  // (não cabe em `LyMotion`), é o ritmo de um loop infinito enquanto a
  // rede não responde.
  static const _pulseDuration = Duration(milliseconds: 900);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _pulseDuration,
  )..repeat(reverse: true);
  late final Animation<double> _pulse = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Opacity(
        opacity: 0.4 + (_pulse.value * 0.35),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceElevated,
            borderRadius: widget.borderRadius ?? LyRadius.sm,
          ),
          child: SizedBox(width: widget.width, height: widget.height),
        ),
      ),
    );
  }
}

/// Uma linha de texto fantasma — o caso mais comum de [LySkeletonBox].
class LySkeletonLine extends StatelessWidget {
  const LySkeletonLine({super.key, this.width, this.height = 14});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      LySkeletonBox(width: width, height: height);
}

/// Uma "linha de lista" fantasma: círculo (avatar/mídia) + duas linhas de
/// texto ao lado — a silhueta comum de conversa, mensagem e sessão recente.
class LySkeletonListTile extends StatelessWidget {
  const LySkeletonListTile({super.key, this.avatarSize = 48});

  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        LySkeletonBox(
          width: avatarSize,
          height: avatarSize,
          borderRadius: LyRadius.md,
        ),
        const SizedBox(width: LySpace.x3),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LySkeletonLine(width: 160),
              SizedBox(height: LySpace.x2),
              LySkeletonLine(width: double.infinity, height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
