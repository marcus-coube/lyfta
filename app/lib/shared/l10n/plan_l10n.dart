import '../../core/l10n/gen/app_localizations.dart';
import '../domain/plan.dart';

/// Rótulo da unidade de alvo (ADR-012 §4). O aluno vê no player a mesma
/// unidade que o professor escolheu no builder — daí morar em `shared/`.
String targetUnitLabel(AppLocalizations l10n, TargetUnit unit) => switch (unit) {
      TargetUnit.kg => l10n.builderTargetKg,
      TargetUnit.percent1rm => l10n.builderTargetPercent1rm,
      TargetUnit.rpe => l10n.builderTargetRpe,
      TargetUnit.rir => l10n.builderTargetRir,
    };

/// Rótulo do tipo de bloco (ADR-004 §1).
String blockTypeLabel(AppLocalizations l10n, BlockType type) => switch (type) {
      BlockType.straight => l10n.builderBlockStraight,
      BlockType.superset => l10n.builderBlockSuperset,
      BlockType.dropset => l10n.builderBlockDropset,
      BlockType.restPause => l10n.builderBlockRestPause,
      BlockType.circuit => l10n.builderBlockCircuit,
    };
