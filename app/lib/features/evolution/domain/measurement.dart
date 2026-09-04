/// Medidas corporais digitadas (ADR-012 §2) — `assessment`, P2.3.
///
/// Todos os campos numéricos são opcionais: o aluno registra o que mediu
/// naquele dia, não a ficha inteira.
class BodyMeasurement {
  const BodyMeasurement({
    required this.id,
    required this.studentId,
    required this.measuredAt,
    required this.createdAt,
    this.weightKg,
    this.heightCm,
    this.neckCm,
    this.shoulderCm,
    this.chestCm,
    this.waistCm,
    this.abdomenCm,
    this.hipCm,
    this.armLCm,
    this.armRCm,
    this.thighLCm,
    this.thighRCm,
    this.calfLCm,
    this.calfRCm,
    this.notes = '',
  });

  factory BodyMeasurement.fromJson(Map<String, dynamic> json) {
    double? dbl(String key) => (json[key] as num?)?.toDouble();
    return BodyMeasurement(
      id: json['id'] as String,
      studentId: json['student_id'] as String? ?? '',
      measuredAt: DateTime.parse(json['measured_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      weightKg: dbl('weight_kg'),
      heightCm: dbl('height_cm'),
      neckCm: dbl('neck_cm'),
      shoulderCm: dbl('shoulder_cm'),
      chestCm: dbl('chest_cm'),
      waistCm: dbl('waist_cm'),
      abdomenCm: dbl('abdomen_cm'),
      hipCm: dbl('hip_cm'),
      armLCm: dbl('arm_l_cm'),
      armRCm: dbl('arm_r_cm'),
      thighLCm: dbl('thigh_l_cm'),
      thighRCm: dbl('thigh_r_cm'),
      calfLCm: dbl('calf_l_cm'),
      calfRCm: dbl('calf_r_cm'),
      notes: json['notes'] as String? ?? '',
    );
  }

  final String id;
  final String studentId;
  final DateTime measuredAt;
  final DateTime createdAt;
  final double? weightKg;
  final double? heightCm;
  final double? neckCm;
  final double? shoulderCm;
  final double? chestCm;
  final double? waistCm;
  final double? abdomenCm;
  final double? hipCm;
  final double? armLCm;
  final double? armRCm;
  final double? thighLCm;
  final double? thighRCm;
  final double? calfLCm;
  final double? calfRCm;
  final String notes;
}

/// Rascunho de uma medida nova — o que o form da tela Evolução monta antes
/// de mandar pro servidor. Só os campos preenchidos entram no `POST`
/// (`measured_at` é o único obrigatório no schema, mas um registro sem
/// nenhum número não é uma medida).
class MeasurementDraft {
  const MeasurementDraft({
    required this.measuredAt,
    this.weightKg,
    this.heightCm,
    this.neckCm,
    this.shoulderCm,
    this.chestCm,
    this.waistCm,
    this.abdomenCm,
    this.hipCm,
    this.armLCm,
    this.armRCm,
    this.thighLCm,
    this.thighRCm,
    this.calfLCm,
    this.calfRCm,
    this.notes = '',
  });

  final DateTime measuredAt;
  final double? weightKg;
  final double? heightCm;
  final double? neckCm;
  final double? shoulderCm;
  final double? chestCm;
  final double? waistCm;
  final double? abdomenCm;
  final double? hipCm;
  final double? armLCm;
  final double? armRCm;
  final double? thighLCm;
  final double? thighRCm;
  final double? calfLCm;
  final double? calfRCm;
  final String notes;

  /// Ao menos um campo medido. `measured_at` sozinho (com ou sem nota) não
  /// vira uma linha no histórico de medidas — é o que o Aceite chama de
  /// "formulário vazio bloqueado".
  bool get hasAnyValue =>
      weightKg != null ||
      heightCm != null ||
      neckCm != null ||
      shoulderCm != null ||
      chestCm != null ||
      waistCm != null ||
      abdomenCm != null ||
      hipCm != null ||
      armLCm != null ||
      armRCm != null ||
      thighLCm != null ||
      thighRCm != null ||
      calfLCm != null ||
      calfRCm != null;

  Map<String, dynamic> toJson() {
    final iso = measuredAt.toIso8601String();
    return {
      'measured_at': iso.substring(0, 10),
      if (weightKg != null) 'weight_kg': weightKg,
      if (heightCm != null) 'height_cm': heightCm,
      if (neckCm != null) 'neck_cm': neckCm,
      if (shoulderCm != null) 'shoulder_cm': shoulderCm,
      if (chestCm != null) 'chest_cm': chestCm,
      if (waistCm != null) 'waist_cm': waistCm,
      if (abdomenCm != null) 'abdomen_cm': abdomenCm,
      if (hipCm != null) 'hip_cm': hipCm,
      if (armLCm != null) 'arm_l_cm': armLCm,
      if (armRCm != null) 'arm_r_cm': armRCm,
      if (thighLCm != null) 'thigh_l_cm': thighLCm,
      if (thighRCm != null) 'thigh_r_cm': thighRCm,
      if (calfLCm != null) 'calf_l_cm': calfLCm,
      if (calfRCm != null) 'calf_r_cm': calfRCm,
      'notes': notes,
    };
  }
}
