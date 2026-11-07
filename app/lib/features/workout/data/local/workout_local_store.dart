import '../../domain/workout_event.dart';

/// O treino do dia como está guardado no device: o JSON cru de
/// `GET /v1/me/today` e quando ele foi baixado.
class CachedToday {
  const CachedToday({required this.payload, required this.fetchedAt});

  final String payload;
  final DateTime fetchedAt;
}

/// Um evento ainda não confirmado pelo servidor, com quantas tentativas de
/// despacho já levou (entra no backoff do worker de sync).
class PendingEvent {
  const PendingEvent({required this.event, required this.attempts});

  final WorkoutEvent event;
  final int attempts;
}

/// Fonte de verdade **local** da execução de treino (ADR-003 §3).
///
/// A UI lê sempre daqui; a rede só hidrata (pull do `/me/today`) e despacha
/// (push da fila). Nenhum caminho da tela depende de conexão.
///
/// A implementação persistente é SQLite via Drift
/// (`DriftWorkoutStore`, mobile/desktop). Na web a mesma interface é servida
/// em memória — ver `workout_store_factory_web.dart` para o porquê.
abstract interface class WorkoutLocalStore {
  /// Guarda o payload inteiro do treino do dia, substituindo o anterior.
  Future<void> saveToday(String studentId, String payload);

  Future<CachedToday?> readToday(String studentId);

  /// Enfileira um fato da execução. Reenfileirar o mesmo `client_id` é
  /// no-op — a fila é append-only e idempotente como o servidor.
  Future<void> enqueue(String studentId, WorkoutEvent event);

  /// Os eventos pendentes na ordem em que foram criados: `session_start`
  /// precisa chegar antes dos `set_log` da mesma sessão.
  Future<List<PendingEvent>> pending(String studentId, {int limit});

  Future<int> pendingCount(String studentId);

  Future<void> removePending(List<String> clientIds);

  /// Marca uma tentativa de despacho que falhou por rede.
  Future<void> registerAttempt(List<String> clientIds);

  Future<void> saveSession(String studentId, LocalSession session);

  /// A sessão aberta do aluno, se ele fechou o app no meio do treino.
  Future<LocalSession?> openSession(String studentId);

  Future<void> finishSession(String clientId, DateTime finishedAt);

  /// Se o aluno concluiu no aparelho o dia [dayId] depois de [since] — é o
  /// treino do cache já feito offline, que o servidor ainda não sabe.
  Future<bool> finishedDaySince(String studentId, String dayId, DateTime since);

  Future<void> saveSetLog(String studentId, LocalSetLog log);

  /// Os logs de uma sessão já com as revisões aplicadas: um log revisado
  /// some da leitura, exatamente como no servidor (P1.5).
  Future<List<LocalSetLog>> setLogs(String sessionClientId);

  /// Apaga tudo — troca de usuário no mesmo device não pode misturar
  /// execução de duas pessoas.
  Future<void> clear();

  Future<void> close();
}

/// Aplica as revisões sobre a lista crua de logs: quem foi revisado sai, e o
/// revisor ocupa o lugar dele (mesmo exercício, mesma série).
List<LocalSetLog> applyRevisions(List<LocalSetLog> raw) {
  final revised = <String>{
    for (final log in raw)
      if (log.revises != null) log.revises!,
  };
  return [
    for (final log in raw)
      if (!revised.contains(log.clientId)) log,
  ];
}
