import 'bioimpedance.dart';
import '../../profile/domain/student_profile.dart';
import 'measurement.dart';

/// Deltas do resumo (`GET /v1/students/{id}/summary`, P2.3): a diferença
/// entre o registro mais recente e o anterior. Nulo — não zero — quando falta
/// o lado anterior, mesmo critério do restante da tela Evolução (P2.1/P2.4):
/// "não dá para saber" não pode desenhar como "não mudou nada".
class EvolutionSummaryDeltas {
  const EvolutionSummaryDeltas({this.weightKg, this.bodyFatPct, this.waistCm});

  factory EvolutionSummaryDeltas.fromJson(Map<String, dynamic> json) {
    double? dbl(String key) => (json[key] as num?)?.toDouble();
    return EvolutionSummaryDeltas(
      weightKg: dbl('weight_kg'),
      bodyFatPct: dbl('body_fat_pct'),
      waistCm: dbl('waist_cm'),
    );
  }

  final double? weightKg;
  final double? bodyFatPct;
  final double? waistCm;
}

/// Resumo do aluno que o coach vê na aba Resumo da ficha (P2.5): última
/// medida, última bioimpedância, contagem de fotos, os deltas acima e, desde a
/// P5.5, objetivo e lesões ativas. Só o
/// coach lê essa rota — a tela do aluno já tem as três listas completas.
class EvolutionSummary {
  const EvolutionSummary({
    required this.photoCount,
    required this.deltas,
    this.goal,
    this.activeInjuries = const [],
    this.latestMeasurement,
    this.latestBioimpedance,
  });

  factory EvolutionSummary.fromJson(Map<String, dynamic> json) {
    final measurement = json['latest_measurement'] as Map<String, dynamic>?;
    final bioimpedance = json['latest_bioimpedance'] as Map<String, dynamic>?;
    return EvolutionSummary(
      latestMeasurement:
          measurement == null ? null : BodyMeasurement.fromJson(measurement),
      latestBioimpedance: bioimpedance == null
          ? null
          : BioimpedanceRecord.fromJson(bioimpedance),
      photoCount: json['photo_count'] as int? ?? 0,
      deltas: EvolutionSummaryDeltas.fromJson(
        json['deltas'] as Map<String, dynamic>? ?? const {},
      ),
      goal: json['goal'] as String?,
      activeInjuries: (json['active_injuries'] as List<dynamic>? ?? const [])
          .map((raw) => Injury.fromJson(raw as Map<String, dynamic>))
          .toList(),
    );
  }

  final BodyMeasurement? latestMeasurement;
  final BioimpedanceRecord? latestBioimpedance;
  final int photoCount;
  final EvolutionSummaryDeltas deltas;

  /// Objetivo e lesões ativas da anamnese (P5.3); nulo/vazio sem anamnese.
  final String? goal;
  final List<Injury> activeInjuries;
}
