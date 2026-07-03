import 'package:flutter/animation.dart';

/// Durações e curvas padrão. Micro-interações usam [fast]; transições de
/// tela, [normal].
abstract final class LyMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve ease = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
}
