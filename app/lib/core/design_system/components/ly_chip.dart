import 'package:flutter/material.dart';

import '../theme/ly_theme.dart';
import '../tokens/ly_radius.dart';
import '../tokens/ly_spacing.dart';
import '../tokens/ly_typography.dart';

/// Chip informativo em pílula: ícone + texto numa cor de acento do tema.
///
/// Com [onInfo], ganha um botão (i) ao fim com alvo de toque de 48 dp
/// ([infoTooltip] é o rótulo de acessibilidade, já traduzido por quem chama).
class LyChip extends StatelessWidget {
  const LyChip({
    required this.icon,
    required this.text,
    required this.color,
    this.onInfo,
    this.infoTooltip,
    this.infoKey,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onInfo;
  final String? infoTooltip;
  final Key? infoKey;

  /// Alvo mínimo de toque do (i).
  static const double infoTouchTarget = 48;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LySpace.x2,
        vertical: LySpace.x1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: LyRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: LySpace.x1),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LyType.caption(context.ly.textPrimary),
            ),
          ),
        ],
      ),
    );
    if (onInfo == null) return pill;

    // O alvo de 48 dp é maior que a pílula: o botão fica ao lado, sem inflar
    // a altura do chip (o espaço extra é do toque, não do visual).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: pill),
        IconButton(
          key: infoKey,
          onPressed: onInfo,
          tooltip: infoTooltip,
          icon: Icon(Icons.info_outline, size: 18, color: color),
          constraints: const BoxConstraints(
            minWidth: infoTouchTarget,
            minHeight: infoTouchTarget,
          ),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}
