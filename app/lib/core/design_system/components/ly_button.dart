import 'package:flutter/material.dart';

import '../theme/ly_theme.dart';
import '../tokens/ly_elevation.dart';
import '../tokens/ly_motion.dart';
import '../tokens/ly_radius.dart';
import '../tokens/ly_spacing.dart';
import '../tokens/ly_typography.dart';

enum LyButtonVariant { primary, secondary, ghost }

/// Botão padrão da Lyfta.
///
/// `primary` é o CTA (lime) — no máximo um por tela. `secondary` para ações
/// alternativas e `ghost` para ações discretas/links.
class LyButton extends StatelessWidget {
  const LyButton({
    required this.label,
    super.key,
    this.onPressed,
    this.variant = LyButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final LyButtonVariant variant;
  final Widget? icon;
  final bool loading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    final (Color bg, Color fg, BoxBorder? border, List<BoxShadow> shadow) =
        switch (variant) {
      LyButtonVariant.primary => (
          c.accent,
          c.onAccent,
          null,
          LyElevation.accentGlow,
        ),
      LyButtonVariant.secondary => (
          c.surfaceElevated,
          c.textPrimary,
          Border.all(color: c.border),
          LyElevation.none,
        ),
      LyButtonVariant.ghost => (
          Colors.transparent,
          c.textSecondary,
          null,
          LyElevation.none,
        ),
    };

    final enabled = onPressed != null && !loading;

    final child = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        else ...[
          if (icon != null) ...[
            IconTheme(data: IconThemeData(color: fg, size: 18), child: icon!),
            const SizedBox(width: LySpace.x2),
          ],
          Text(label, style: LyType.label(fg).copyWith(fontSize: 15)),
        ],
      ],
    );

    return AnimatedOpacity(
      duration: LyMotion.fast,
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: LyRadius.md,
            border: border,
            boxShadow: shadow,
          ),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: LyRadius.md,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LySpace.x5,
                vertical: LySpace.x4,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
