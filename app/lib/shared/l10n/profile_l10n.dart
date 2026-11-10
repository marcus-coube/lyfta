import '../../core/l10n/gen/app_localizations.dart';

/// Rótulos da anamnese (P5.5). O servidor guarda códigos estáveis
/// (ADR-011 §5); código desconhecido (servidor mais novo que o app) cai no
/// próprio código em vez de quebrar a tela.

String goalLabel(AppLocalizations l10n, String code) {
  return switch (code) {
    'hypertrophy' => l10n.goalHypertrophy,
    'weight_loss' => l10n.goalWeightLoss,
    'strength' => l10n.goalStrength,
    'conditioning' => l10n.goalConditioning,
    'health' => l10n.goalHealth,
    'rehab' => l10n.goalRehab,
    'other' => l10n.goalOther,
    _ => code,
  };
}

String experienceLabel(AppLocalizations l10n, String code) {
  return switch (code) {
    'beginner' => l10n.experienceBeginner,
    'intermediate' => l10n.experienceIntermediate,
    'advanced' => l10n.experienceAdvanced,
    _ => code,
  };
}

String bodyRegionLabel(AppLocalizations l10n, String code) {
  return switch (code) {
    'neck' => l10n.bodyRegionNeck,
    'shoulder' => l10n.bodyRegionShoulder,
    'elbow' => l10n.bodyRegionElbow,
    'wrist_hand' => l10n.bodyRegionWristHand,
    'upper_back' => l10n.bodyRegionUpperBack,
    'lower_back' => l10n.bodyRegionLowerBack,
    'chest' => l10n.bodyRegionChest,
    'hip' => l10n.bodyRegionHip,
    'knee' => l10n.bodyRegionKnee,
    'ankle_foot' => l10n.bodyRegionAnkleFoot,
    'other' => l10n.bodyRegionOther,
    _ => code,
  };
}
