import '../../../shared/domain/exercise.dart';

/// Modelos do histórico de carga por exercício (`workout`, P2.1 → P2.4): a
/// série temporal que vira o gráfico de progressão, mais o índice de
/// exercícios já treinados que alimenta o seletor da tela Evolução.

/// A melhor série da sessão — a que o aluno lembra ("bati 45 por 8").
class TopSet {
  const TopSet({this.setNo, this.repsDone, this.loadKg});

  factory TopSet.fromJson(Map<String, dynamic> json) {
    return TopSet(
      setNo: json['set_no'] as int?,
      repsDone: json['reps_done'] as int?,
      loadKg: (json['load_kg'] as num?)?.toDouble(),
    );
  }

  final int? setNo;
  final int? repsDone;
  final double? loadKg;
}

/// Um ponto do gráfico: uma sessão em que o exercício foi treinado.
///
/// [maxLoadKg] é nulo — não zero — em exercício sem carga (corpo livre,
/// trabalho por tempo): zero desenharia uma linha no chão em vez de trocar
/// de métrica.
class ExerciseHistoryPoint {
  const ExerciseHistoryPoint({
    required this.sessionId,
    required this.performedAt,
    required this.sets,
    required this.maxLoadKg,
    required this.totalVolumeKg,
    required this.topSet,
  });

  factory ExerciseHistoryPoint.fromJson(Map<String, dynamic> json) {
    return ExerciseHistoryPoint(
      sessionId: json['session_id'] as String,
      performedAt: DateTime.parse(json['performed_at'] as String),
      sets: json['sets'] as int? ?? 0,
      maxLoadKg: (json['max_load_kg'] as num?)?.toDouble(),
      totalVolumeKg: (json['total_volume_kg'] as num?)?.toDouble() ?? 0,
      topSet: TopSet.fromJson(
        json['top_set'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  final String sessionId;
  final DateTime performedAt;
  final int sets;
  final double? maxLoadKg;
  final double totalVolumeKg;
  final TopSet topSet;
}

/// Uma página do histórico — cursor keyset `(performed_at, session_id)`
/// descendente (P2.1): a tela abre no presente e pagina para trás.
class ExerciseHistoryPage {
  const ExerciseHistoryPage({
    required this.exerciseId,
    required this.items,
    this.nextCursor,
  });

  factory ExerciseHistoryPage.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map(
          (raw) => ExerciseHistoryPoint.fromJson(raw as Map<String, dynamic>),
        )
        .toList();
    final cursor = json['next_cursor'] as String?;
    return ExerciseHistoryPage(
      exerciseId: json['exercise_id'] as String? ?? '',
      items: items,
      nextCursor: (cursor ?? '').isEmpty ? null : cursor,
    );
  }

  final String exerciseId;
  final List<ExerciseHistoryPoint> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Um item do índice `/exercises/logged`: o exercício já treinado pelo
/// menos uma vez, com o exercício resolvido no locale do usuário.
class LoggedExercise {
  const LoggedExercise({
    required this.sessions,
    required this.lastPerformedAt,
    required this.exercise,
  });

  factory LoggedExercise.fromJson(Map<String, dynamic> json) {
    return LoggedExercise(
      sessions: json['sessions'] as int? ?? 0,
      lastPerformedAt: DateTime.parse(json['last_performed_at'] as String),
      exercise: Exercise.fromJson(json['exercise'] as Map<String, dynamic>),
    );
  }

  final int sessions;
  final DateTime lastPerformedAt;
  final Exercise exercise;
}
