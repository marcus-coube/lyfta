import '../../core/l10n/gen/app_localizations.dart';

/// Tradução dos **códigos** da taxonomia de exercícios (ADR-010 §4).
///
/// O backend só conhece códigos (`chest`, `barbell`) e nunca devolve texto de
/// UI — quem traduz é o app (ADR-011 §5). Este arquivo é a única ponte entre
/// código e rótulo; um `switch` exaustivo é de propósito: código novo no
/// backend quebra aqui, não silenciosamente na tela.
String muscleLabel(AppLocalizations l10n, String code) => switch (code) {
      'chest' => l10n.muscleChest,
      'back' => l10n.muscleBack,
      'lats' => l10n.muscleLats,
      'traps' => l10n.muscleTraps,
      'lower_back' => l10n.muscleLowerBack,
      'shoulders' => l10n.muscleShoulders,
      'biceps' => l10n.muscleBiceps,
      'triceps' => l10n.muscleTriceps,
      'forearms' => l10n.muscleForearms,
      'abs' => l10n.muscleAbs,
      'obliques' => l10n.muscleObliques,
      'quadriceps' => l10n.muscleQuadriceps,
      'hamstrings' => l10n.muscleHamstrings,
      'glutes' => l10n.muscleGlutes,
      'calves' => l10n.muscleCalves,
      'adductors' => l10n.muscleAdductors,
      'abductors' => l10n.muscleAbductors,
      'full_body' => l10n.muscleFullBody,
      _ => code,
    };

String equipmentLabel(AppLocalizations l10n, String code) => switch (code) {
      'barbell' => l10n.equipmentBarbell,
      'dumbbell' => l10n.equipmentDumbbell,
      'machine' => l10n.equipmentMachine,
      'cable' => l10n.equipmentCable,
      'smith' => l10n.equipmentSmith,
      'bodyweight' => l10n.equipmentBodyweight,
      'kettlebell' => l10n.equipmentKettlebell,
      'band' => l10n.equipmentBand,
      'bench' => l10n.equipmentBench,
      'other' => l10n.equipmentOther,
      _ => code,
    };

String levelLabel(AppLocalizations l10n, String code) => switch (code) {
      'beginner' => l10n.levelBeginner,
      'intermediate' => l10n.levelIntermediate,
      'advanced' => l10n.levelAdvanced,
      _ => code,
    };
