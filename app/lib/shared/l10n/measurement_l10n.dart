import '../../core/l10n/gen/app_localizations.dart';

/// Rótulos dos campos de medida corporal e bioimpedância (ADR-011 §5: são
/// campos estruturados, não texto livre, então o app traduz por código —
/// igual à taxonomia da biblioteca em `taxonomy_l10n.dart`).
///
/// Os códigos são os nomes de campo do JSON do `assessment` (P2.3), para o
/// form e a lista compartilharem a mesma chave sem duplicar o `switch`.

const List<String> bodyMeasurementFields = [
  'weight_kg',
  'height_cm',
  'neck_cm',
  'shoulder_cm',
  'chest_cm',
  'waist_cm',
  'abdomen_cm',
  'hip_cm',
  'arm_l_cm',
  'arm_r_cm',
  'thigh_l_cm',
  'thigh_r_cm',
  'calf_l_cm',
  'calf_r_cm',
];

String measurementFieldLabel(AppLocalizations l10n, String code) {
  return switch (code) {
    'weight_kg' => l10n.measurementFieldWeightKg,
    'height_cm' => l10n.measurementFieldHeightCm,
    'neck_cm' => l10n.measurementFieldNeckCm,
    'shoulder_cm' => l10n.measurementFieldShoulderCm,
    'chest_cm' => l10n.measurementFieldChestCm,
    'waist_cm' => l10n.measurementFieldWaistCm,
    'abdomen_cm' => l10n.measurementFieldAbdomenCm,
    'hip_cm' => l10n.measurementFieldHipCm,
    'arm_l_cm' => l10n.measurementFieldArmLCm,
    'arm_r_cm' => l10n.measurementFieldArmRCm,
    'thigh_l_cm' => l10n.measurementFieldThighLCm,
    'thigh_r_cm' => l10n.measurementFieldThighRCm,
    'calf_l_cm' => l10n.measurementFieldCalfLCm,
    'calf_r_cm' => l10n.measurementFieldCalfRCm,
    _ => code,
  };
}

const List<String> bioimpedanceFields = [
  'body_fat_pct',
  'muscle_mass_kg',
  'visceral_fat',
  'body_water_pct',
  'bone_mass_kg',
  'bmr_kcal',
];

String bioimpedanceFieldLabel(AppLocalizations l10n, String code) {
  return switch (code) {
    'body_fat_pct' => l10n.bioimpedanceFieldBodyFatPct,
    'muscle_mass_kg' => l10n.bioimpedanceFieldMuscleMassKg,
    'visceral_fat' => l10n.bioimpedanceFieldVisceralFat,
    'body_water_pct' => l10n.bioimpedanceFieldBodyWaterPct,
    'bone_mass_kg' => l10n.bioimpedanceFieldBoneMassKg,
    'bmr_kcal' => l10n.bioimpedanceFieldBmrKcal,
    _ => code,
  };
}
