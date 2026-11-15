import 'package:intl/intl.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/domain/plan.dart';
import '../../../shared/l10n/plan_l10n.dart';

/// Carga em texto curto: `40`, `42,5` (separador decimal do `locale` —
/// ADR-011 §4, nunca `toString()` cru, que sempre usa `.`). O `.0` do double
/// não diz nada para quem está de pé na frente da barra.
String formatLoad(double value, String locale) {
  return NumberFormat('#,##0.##', locale).format(value);
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
  // Sem unidade é kg: o builder grava `target_load_kg` sem `target_unit`
  // quando o professor não troca a unidade (`set_editor.dart`).
  final unit = set.targetUnit ?? TargetUnit.kg;
  // O alvo mora em duas colunas: absoluto em kg, relativo em %1RM/RPE/RIR.
  final value = unit == TargetUnit.kg ? set.targetLoadKg : set.targetValue;
  if (value == null) return null;
  if (unit == TargetUnit.kg) {
    return l10n.sessionTargetKg(formatLoad(value, l10n.localeName));
  }
  return l10n.sessionTargetWithUnit(
    formatLoad(value, l10n.localeName),
    targetUnitLabel(l10n, unit),
  );
}
