import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/domain/plan.dart';
import '../../../shared/l10n/plan_l10n.dart';

/// Carga em texto curto: `40`, `42.5`. O `.0` do double não diz nada para
/// quem está de pé na frente da barra.
String formatLoad(double value) {
  final rounded = (value * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toString();
}

/// A prescrição de uma série em uma linha: repetições e alvo, do jeito que o
/// professor escreveu no builder (ADR-012 §4).
String prescriptionLabel(AppLocalizations l10n, PrescribedSet set) {
  final parts = <String>[_repsLabel(l10n, set)];
  final target = _targetLabel(l10n, set);
  if (target != null) parts.add(target);
  return parts.join(' · ');
}

String _repsLabel(AppLocalizations l10n, PrescribedSet set) {
  final min = set.repsMin;
  final max = set.repsMax;
  if (min != null && max != null && min != max) {
    return l10n.sessionTargetRepsRange(min, max);
  }
  final reps = min ?? max;
  if (reps == null) return l10n.sessionTargetFreeReps;
  return l10n.sessionTargetReps(reps);
}

String? _targetLabel(AppLocalizations l10n, PrescribedSet set) {
  final unit = set.targetUnit;
  if (unit == null) return null;
  // O alvo mora em duas colunas: absoluto em kg, relativo em %1RM/RPE/RIR.
  final value = unit == TargetUnit.kg ? set.targetLoadKg : set.targetValue;
  if (value == null) return null;
  return l10n.sessionTargetWithUnit(
    formatLoad(value),
    targetUnitLabel(l10n, unit),
  );
}
