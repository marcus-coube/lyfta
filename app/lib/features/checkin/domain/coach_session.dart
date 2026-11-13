import '../../../shared/domain/plan.dart';
import '../../workout/domain/session_metrics.dart';

/// Resumo de uma sessão do aluno visto pelo professor (P11.2) — o que o
/// `workout` devolve em `POST /v1/students/{id}/sessions/lookup`.
class CoachSession {
  const CoachSession({
    required this.clientId,
    required this.dayLabel,
    required this.planTitle,
    required this.startedAt,
    required this.setsCount,
    required this.repsTotal,
    required this.volumeKg,
    this.finishedAt,
    this.durationSeconds,
  });

  factory CoachSession.fromJson(Map<String, dynamic> json) {
    return CoachSession(
      clientId: json['client_id'] as String,
      dayLabel: json['day_label'] as String? ?? '',
      planTitle: json['plan_title'] as String? ?? '',
      startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
      finishedAt: json['finished_at'] == null
          ? null
          : DateTime.parse(json['finished_at'] as String).toLocal(),
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      setsCount: (json['sets_count'] as num?)?.toInt() ?? 0,
      repsTotal: (json['reps_total'] as num?)?.toInt() ?? 0,
      volumeKg: (json['volume_kg'] as num?)?.toDouble() ?? 0,
    );
  }

  final String clientId;
  final String dayLabel;
  final String planTitle;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// Nulo sem fim da sessão ou com relógio do device fora do razoável
  /// (negativo ou > 12 h — o servidor decide, ADR-003).
  final int? durationSeconds;
  final int setsCount;
  final int repsTotal;
  final double volumeKg;

  /// As mesmas quatro métricas do resumo do aluno ([SessionMetrics]).
  SessionMetrics get metrics => SessionMetrics(
        sets: setsCount,
        reps: repsTotal,
        volumeKg: volumeKg,
        duration: Duration(seconds: durationSeconds ?? 0),
      );
}

/// O que o aluno de fato fez numa série — último log efetivo.
class CoachSetDone {
  const CoachSetDone({
    required this.performedAt,
    required this.revised,
    this.repsDone,
    this.loadKg,
    this.rpe,
  });

  factory CoachSetDone.fromJson(Map<String, dynamic> json) => CoachSetDone(
        repsDone: (json['reps_done'] as num?)?.toInt(),
        loadKg: (json['load_kg'] as num?)?.toDouble(),
        rpe: (json['rpe'] as num?)?.toDouble(),
        performedAt: DateTime.parse(json['performed_at'] as String).toLocal(),
        revised: json['revised'] as bool? ?? false,
      );

  final int? repsDone;
  final double? loadKg;
  final double? rpe;
  final DateTime performedAt;

  /// Corrigida depois (evento `revises`, ADR-003 §5).
  final bool revised;
}

class CoachSet {
  const CoachSet({
    required this.setNo,
    required this.prescribed,
    this.label,
    this.variationName,
    this.done,
  });

  factory CoachSet.fromJson(Map<String, dynamic> json) {
    final p = json['prescribed'] as Map<String, dynamic>? ?? const {};
    final done = json['done'] as Map<String, dynamic>?;
    final variation = json['variation_name'] as String?;
    return CoachSet(
      setNo: (json['set_no'] as num?)?.toInt() ?? 0,
      label: json['label'] as String?,
      variationName: (variation ?? '').isEmpty ? null : variation,
      prescribed: PrescribedSet(
        repsMin: (p['reps_min'] as num?)?.toInt(),
        repsMax: (p['reps_max'] as num?)?.toInt(),
        targetLoadKg: (p['target_load_kg'] as num?)?.toDouble(),
        targetUnit: TargetUnit.tryParse(p['target_unit'] as String?),
        targetValue: (p['target_value'] as num?)?.toDouble(),
      ),
      done: done == null ? null : CoachSetDone.fromJson(done),
    );
  }

  /// Número da série no snapshot (o que o aluno viu).
  final int setNo;
  final String? label;
  final String? variationName;
  final PrescribedSet prescribed;

  /// Nulo = série não feita.
  final CoachSetDone? done;
}

class CoachExercise {
  const CoachExercise({
    required this.exerciseId,
    required this.name,
    required this.sets,
  });

  factory CoachExercise.fromJson(Map<String, dynamic> json) => CoachExercise(
        exerciseId: json['exercise_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        sets: [
          for (final raw in json['sets'] as List<dynamic>? ?? const [])
            CoachSet.fromJson(raw as Map<String, dynamic>),
        ],
      );

  final String exerciseId;
  final String name;
  final List<CoachSet> sets;
}

class CoachBlock {
  const CoachBlock({required this.type, required this.exercises});

  factory CoachBlock.fromJson(Map<String, dynamic> json) => CoachBlock(
        type: BlockType.fromCode(json['block_type'] as String?),
        exercises: [
          for (final raw in json['exercises'] as List<dynamic>? ?? const [])
            CoachExercise.fromJson(raw as Map<String, dynamic>),
        ],
      );

  final BlockType type;
  final List<CoachExercise> exercises;
}

/// Sessão + exercícios (`GET /v1/students/{id}/sessions/{client_id}`).
class CoachSessionDetail {
  const CoachSessionDetail({required this.session, required this.blocks});

  factory CoachSessionDetail.fromJson(Map<String, dynamic> json) {
    return CoachSessionDetail(
      session: CoachSession.fromJson(json),
      blocks: [
        for (final raw in json['blocks'] as List<dynamic>? ?? const [])
          CoachBlock.fromJson(raw as Map<String, dynamic>),
      ],
    );
  }

  final CoachSession session;
  final List<CoachBlock> blocks;
}
