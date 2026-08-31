import 'dart:convert';

import '../../../shared/domain/plan.dart';

/// Estado da tela Hoje. São **códigos** vindos do servidor (P1.5), não texto:
/// quem traduz é o app (ADR-011 §5).
enum TodayStatus {
  noPlan,
  restDay,
  ready;

  static TodayStatus fromCode(String? code) => switch (code) {
        'rest_day' => TodayStatus.restDay,
        'ready' => TodayStatus.ready,
        _ => TodayStatus.noPlan,
      };
}

/// Cabeçalho do plano ativo do aluno.
class TodayPlanRef {
  const TodayPlanRef({
    required this.id,
    required this.title,
    required this.versionId,
    required this.versionNo,
  });

  factory TodayPlanRef.fromJson(Map<String, dynamic> json) {
    return TodayPlanRef(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      versionId: json['version_id'] as String? ?? '',
      versionNo: json['version_no'] as int? ?? 0,
    );
  }

  final String id;
  final String title;
  final String versionId;
  final int versionNo;
}

/// Uma série da última vez em que o exercício foi executado.
class PreviousLoadSet {
  const PreviousLoadSet({
    required this.setNo,
    this.repsDone,
    this.loadKg,
    this.rpe,
  });

  factory PreviousLoadSet.fromJson(Map<String, dynamic> json) {
    return PreviousLoadSet(
      setNo: json['set_no'] as int? ?? 0,
      repsDone: json['reps_done'] as int?,
      loadKg: (json['load_kg'] as num?)?.toDouble(),
      rpe: (json['rpe'] as num?)?.toDouble(),
    );
  }

  final int setNo;
  final int? repsDone;
  final double? loadKg;
  final double? rpe;
}

/// Carga anterior de um exercício (ADR-004): **todas** as séries da última
/// sessão em que ele apareceu, não só a última série — é o que o player
/// precisa para pré-preencher linha a linha.
class PreviousLoad {
  const PreviousLoad({
    required this.exerciseId,
    required this.performedAt,
    required this.sets,
  });

  factory PreviousLoad.fromJson(Map<String, dynamic> json) {
    return PreviousLoad(
      exerciseId: json['exercise_id'] as String? ?? '',
      performedAt:
          DateTime.tryParse(json['performed_at'] as String? ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      sets: (json['sets'] as List<dynamic>? ?? const [])
          .map((raw) => PreviousLoadSet.fromJson(raw as Map<String, dynamic>))
          .toList(),
    );
  }

  final String exerciseId;
  final DateTime performedAt;
  final List<PreviousLoadSet> sets;

  /// A série de número [setNo], quando ela existiu na última execução.
  PreviousLoadSet? setNoOrNull(int setNo) {
    for (final s in sets) {
      if (s.setNo == setNo) return s;
    }
    return null;
  }

  /// Maior carga registrada — o que o chip "carga anterior" mostra.
  double? get topLoadKg {
    double? top;
    for (final s in sets) {
      final load = s.loadKg;
      if (load == null) continue;
      if (top == null || load > top) top = load;
    }
    return top;
  }
}

/// Resumo de uma sessão já concluída (últimas 3, P1.5).
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.dayLabel,
    required this.startedAt,
    required this.totalSets,
    required this.totalVolumeKg,
    this.finishedAt,
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      id: json['id'] as String? ?? '',
      dayLabel: json['day_label'] as String? ?? '',
      startedAt:
          DateTime.tryParse(json['started_at'] as String? ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      finishedAt:
          DateTime.tryParse(json['finished_at'] as String? ?? '')?.toLocal(),
      totalSets: json['total_sets'] as int? ?? 0,
      totalVolumeKg: (json['total_volume_kg'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final String dayLabel;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int totalSets;
  final double totalVolumeKg;
}

/// O treino do dia inteiro — o payload de `GET /v1/me/today`, que é cacheado
/// **integralmente** no device (ADR-003 §3): tudo que a tela Hoje e o player
/// precisam sai desta única leitura, porque a próxima pode ser sem rede.
class Today {
  const Today({
    required this.status,
    required this.previousLoads,
    required this.recentSessions,
    this.plan,
    this.day,
  });

  factory Today.fromJson(Map<String, dynamic> json) {
    final day = json['day'] as Map<String, dynamic>?;
    final plan = json['plan'] as Map<String, dynamic>?;
    return Today(
      status: TodayStatus.fromCode(json['status'] as String?),
      plan: plan == null ? null : TodayPlanRef.fromJson(plan),
      day: day == null ? null : WorkoutDay.fromJson(day),
      previousLoads: {
        for (final raw in json['previous_loads'] as List<dynamic>? ?? const [])
          (raw as Map<String, dynamic>)['exercise_id'] as String:
              PreviousLoad.fromJson(raw),
      },
      recentSessions: (json['recent_sessions'] as List<dynamic>? ?? const [])
          .map((raw) => SessionSummary.fromJson(raw as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Reconstrói a partir do JSON cru guardado no banco local.
  factory Today.decode(String payload) =>
      Today.fromJson(jsonDecode(payload) as Map<String, dynamic>);

  final TodayStatus status;
  final TodayPlanRef? plan;
  final WorkoutDay? day;
  final Map<String, PreviousLoad> previousLoads;
  final List<SessionSummary> recentSessions;

  bool get hasWorkout => status == TodayStatus.ready && day != null;

  /// O dia achatado na ordem de execução — é como o player caminha pelo
  /// treino.
  ///
  /// O `set_no` é contínuo **por exercício dentro da sessão**, não por bloco:
  /// um exercício que aparece em dois blocos do mesmo dia (aquecimento e
  /// série pesada, por exemplo) numeraria duas vezes "série 1" e as duas
  /// linhas cairiam uma sobre a outra na leitura de carga anterior do P1.5.
  List<ExerciseRun> get runs {
    final used = <String, int>{};
    final out = <ExerciseRun>[];
    for (final block in day?.blocks ?? const <Block>[]) {
      for (final exercise in block.exercises) {
        final offset = used[exercise.exerciseId] ?? 0;
        out.add(
          ExerciseRun(block: block, exercise: exercise, setNoOffset: offset),
        );
        used[exercise.exerciseId] = offset + exercise.sets.length;
      }
    }
    return out;
  }
}

/// Uma aparição de exercício no treino do dia, já com o número da primeira
/// série que ela ocupa na sessão.
class ExerciseRun {
  const ExerciseRun({
    required this.block,
    required this.exercise,
    required this.setNoOffset,
  });

  final Block block;
  final BlockExercise exercise;
  final int setNoOffset;

  String get exerciseId => exercise.exerciseId;

  /// `set_no` (1-based) da série de índice [index] desta aparição.
  int setNoAt(int index) => setNoOffset + index + 1;

  /// Descanso da série: o do set quando prescrito, senão o do bloco.
  Duration restAt(int index) {
    final set = exercise.sets[index];
    return Duration(seconds: set.restSeconds ?? block.restSeconds);
  }
}
