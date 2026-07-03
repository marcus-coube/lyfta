import 'package:flutter/material.dart';

import '../theme/ly_theme.dart';
import '../tokens/ly_elevation.dart';
import '../tokens/ly_radius.dart';
import '../tokens/ly_spacing.dart';

/// Superfície padrão para agrupar conteúdo.
class LyCard extends StatelessWidget {
  const LyCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(LySpace.x6),
    this.onTap,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    final card = Ink(
      decoration: BoxDecoration(
        color: elevated ? c.surfaceElevated : c.surface,
        borderRadius: LyRadius.lg,
        border: Border.all(color: c.border),
        boxShadow: elevated ? LyElevation.low : LyElevation.none,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return Material(color: Colors.transparent, child: card);

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: LyRadius.lg, child: card),
    );
  }
}
