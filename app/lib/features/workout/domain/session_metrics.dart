import 'workout_event.dart';

/// Métricas de uma sessão — **definição única** (P10.2 §2). O servidor
/// calcula o mesmo na P11.1; qualquer mudança aqui muda lá.
///
/// - séries = logs efetivos (corrigir uma série não conta duas vezes);
/// - reps = Σ `reps_done`;
/// - volume = Σ `load × reps`;
/// - duração = fim − início.
class SessionMetrics {
  const SessionMetrics({
    required this.sets,
    required this.reps,
    required this.volumeKg,
    required this.duration,
  });

  /// [logs] pode vir crua ou já com as revisões aplicadas: um log apontado
  /// por `revises` de outro nunca entra na conta (ADR-003 §5).
  factory SessionMetrics.of(
    List<LocalSetLog> logs, {
    required DateTime startedAt,
    required DateTime endedAt,
  }) {
    final revised = <String>{
      for (final log in logs)
        if (log.revises != null) log.revises!,
    };
    final effective = [
      for (final log in logs)
        if (!revised.contains(log.clientId)) log,
    ];
    final elapsed = endedAt.difference(startedAt);
    return SessionMetrics(
      sets: effective.length,
      reps: effective.fold(0, (sum, log) => sum + (log.repsDone ?? 0)),
      volumeKg: effective.fold(0.0, (sum, log) => sum + log.volumeKg),
      duration: elapsed.isNegative ? Duration.zero : elapsed,
    );
  }

  final int sets;
  final int reps;
  final double volumeKg;
  final Duration duration;
}

/// `h:mm:ss` — o formato do cronômetro e da duração do resumo.
String formatClock(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
