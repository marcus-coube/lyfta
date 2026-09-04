/// Leituras de bioimpedância digitadas manualmente (ADR-012 §2 — integração
/// com balança fica fora do MVP 1.0) — `assessment`, P2.3.
class BioimpedanceRecord {
  const BioimpedanceRecord({
    required this.id,
    required this.studentId,
    required this.measuredAt,
    required this.createdAt,
    this.bodyFatPct,
    this.muscleMassKg,
    this.visceralFat,
    this.bodyWaterPct,
    this.boneMassKg,
    this.bmrKcal,
    this.notes = '',
  });

  factory BioimpedanceRecord.fromJson(Map<String, dynamic> json) {
    double? dbl(String key) => (json[key] as num?)?.toDouble();
    return BioimpedanceRecord(
      id: json['id'] as String,
      studentId: json['student_id'] as String? ?? '',
      measuredAt: DateTime.parse(json['measured_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      bodyFatPct: dbl('body_fat_pct'),
      muscleMassKg: dbl('muscle_mass_kg'),
      visceralFat: dbl('visceral_fat'),
      bodyWaterPct: dbl('body_water_pct'),
      boneMassKg: dbl('bone_mass_kg'),
      bmrKcal: json['bmr_kcal'] as int?,
      notes: json['notes'] as String? ?? '',
    );
  }

  final String id;
  final String studentId;
  final DateTime measuredAt;
  final DateTime createdAt;
  final double? bodyFatPct;
  final double? muscleMassKg;
  final double? visceralFat;
  final double? bodyWaterPct;
  final double? boneMassKg;
  final int? bmrKcal;
  final String notes;
}

/// Rascunho de uma leitura nova — mesma regra do [MeasurementDraft]: só os
/// campos preenchidos entram no `POST`, e ao menos um é exigido.
class BioimpedanceDraft {
  const BioimpedanceDraft({
    required this.measuredAt,
    this.bodyFatPct,
    this.muscleMassKg,
    this.visceralFat,
    this.bodyWaterPct,
    this.boneMassKg,
    this.bmrKcal,
    this.notes = '',
  });

  final DateTime measuredAt;
  final double? bodyFatPct;
  final double? muscleMassKg;
  final double? visceralFat;
  final double? bodyWaterPct;
  final double? boneMassKg;
  final int? bmrKcal;
  final String notes;

  bool get hasAnyValue =>
      bodyFatPct != null ||
      muscleMassKg != null ||
      visceralFat != null ||
      bodyWaterPct != null ||
      boneMassKg != null ||
      bmrKcal != null;

  Map<String, dynamic> toJson() {
    final iso = measuredAt.toIso8601String();
    return {
      'measured_at': iso.substring(0, 10),
      if (bodyFatPct != null) 'body_fat_pct': bodyFatPct,
      if (muscleMassKg != null) 'muscle_mass_kg': muscleMassKg,
      if (visceralFat != null) 'visceral_fat': visceralFat,
      if (bodyWaterPct != null) 'body_water_pct': bodyWaterPct,
      if (boneMassKg != null) 'bone_mass_kg': boneMassKg,
      if (bmrKcal != null) 'bmr_kcal': bmrKcal,
      'notes': notes,
    };
  }
}
