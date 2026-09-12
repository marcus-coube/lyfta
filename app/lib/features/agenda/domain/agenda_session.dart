/// Uma sessão sincronizada dentro da janela consultada — o "treino feito" da
/// agenda semanal do aluno (P4.1).
///
/// Espelha o `sessionSummaryDTO` do `workout` (`GET /v1/me/sessions`), mas é
/// declarado de novo em vez de importado de `features/workout/domain/today.dart`:
/// a guideline `docs/guidelines/flutter.md` § Estrutura é explícita — "feature
/// não importa outra feature; o que for comum sobe para shared/ ou core/" —, e
/// o mesmo padrão de duplicação já existe entre `shared/format/metric_format.dart`
/// e `features/workout/presentation/prescription_format.dart`.
class AgendaSession {
  const AgendaSession({
    required this.id,
    required this.dayLabel,
    required this.startedAt,
    required this.totalSets,
    required this.totalVolumeKg,
    this.finishedAt,
  });

  factory AgendaSession.fromJson(Map<String, dynamic> json) {
    return AgendaSession(
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

  /// Nulo quando a sessão nunca foi concluída (aberta e abandonada) — a
  /// agenda ainda mostra o dia como "feito" (houve tentativa), mas sem
  /// duração para exibir.
  Duration? get duration => finishedAt?.difference(startedAt);
}
