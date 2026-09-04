import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../shared/format/metric_format.dart';

/// Selo colorido de variação entre um registro e o anterior — "deltas
/// coloridos" do Aceite da P2.4.
///
/// Cor por sinal, não por campo: diminuir pinta `success`, aumentar pinta
/// `danger`. É uma simplificação consciente (ganhar peso pode ser a meta de
/// alguém) — sem um objetivo declarado por medida, sinalizar "queda = verde"
/// é a leitura mais comum em cintura/gordura, que é a maioria dos campos.
class DeltaBadge extends StatelessWidget {
  const DeltaBadge({required this.value, super.key});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final delta = value;
    if (delta == null || delta == 0) return const SizedBox.shrink();

    final c = context.ly;
    final color = delta < 0 ? c.success : c.danger;
    final icon = delta < 0 ? Icons.arrow_downward : Icons.arrow_upward;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: LySpace.x2, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: LyRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 2),
          Text(formatSignedMetric(delta), style: LyType.caption(color)),
        ],
      ),
    );
  }
}
