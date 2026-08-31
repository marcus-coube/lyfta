import '../../domain/workout_event.dart';
import 'workout_local_store.dart';

/// [WorkoutLocalStore] em memória — a implementação da **web**.
///
/// Na web o Drift precisa de `sqlite3.wasm` e `drift_worker.js` servidos
/// junto do bundle, e a pasta `web/` deste repo é gerada por
/// `flutter create .` (não versionada, ver `app/README.md`): carregar dois
/// binários no build para atender um caso que não existe — aluno treinando
/// no navegador **sem rede** — não se paga. O offline do ADR-003 é do aluno
/// no ginásio, com o celular.
///
/// A consequência é honesta e está anotada no plano: na web a fila vive
/// enquanto a aba viver. Como a aba só existe se houve rede para carregar o
/// app, o worker drena a cada evento e a janela de perda é a de uma
/// requisição.
class MemoryWorkoutStore implements WorkoutLocalStore {
  final Map<String, CachedToday> _today = {};
  final Map<String, _QueuedEvent> _queue = {};
  final Map<String, _StoredSession> _sessions = {};
  final Map<String, LocalSetLog> _logs = {};
  int _seq = 0;

  @override
  Future<void> saveToday(String studentId, String payload) async {
    _today[studentId] = CachedToday(payload: payload, fetchedAt: DateTime.now());
  }

  @override
  Future<CachedToday?> readToday(String studentId) async => _today[studentId];

  @override
  Future<void> enqueue(String studentId, WorkoutEvent event) async {
    _queue.putIfAbsent(
      event.clientId,
      () => _QueuedEvent(studentId, event, _seq++),
    );
  }

  @override
  Future<List<PendingEvent>> pending(String studentId, {int limit = 200}) async {
    final items = _queue.values.where((e) => e.studentId == studentId).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return items
        .take(limit)
        .map((e) => PendingEvent(event: e.event, attempts: e.attempts))
        .toList();
  }

  @override
  Future<int> pendingCount(String studentId) async =>
      _queue.values.where((e) => e.studentId == studentId).length;

  @override
  Future<void> removePending(List<String> clientIds) async {
    for (final id in clientIds) {
      _queue.remove(id);
    }
  }

  @override
  Future<void> registerAttempt(List<String> clientIds) async {
    for (final id in clientIds) {
      final entry = _queue[id];
      if (entry != null) entry.attempts++;
    }
  }

  @override
  Future<void> saveSession(String studentId, LocalSession session) async {
    _sessions[session.clientId] = _StoredSession(studentId, session);
  }

  @override
  Future<LocalSession?> openSession(String studentId) async {
    final open = _sessions.values
        .where((s) => s.studentId == studentId && s.session.isOpen)
        .toList()
      ..sort((a, b) => b.session.startedAt.compareTo(a.session.startedAt));
    return open.isEmpty ? null : open.first.session;
  }

  @override
  Future<void> finishSession(String clientId, DateTime finishedAt) async {
    final stored = _sessions[clientId];
    if (stored == null) return;
    final s = stored.session;
    _sessions[clientId] = _StoredSession(
      stored.studentId,
      LocalSession(
        clientId: s.clientId,
        dayId: s.dayId,
        dayLabel: s.dayLabel,
        dayTitle: s.dayTitle,
        startedAt: s.startedAt,
        finishedAt: finishedAt,
      ),
    );
  }

  @override
  Future<void> saveSetLog(String studentId, LocalSetLog log) async {
    _logs.putIfAbsent(log.clientId, () => log);
  }

  @override
  Future<List<LocalSetLog>> setLogs(String sessionClientId) async {
    final rows = _logs.values
        .where((l) => l.sessionClientId == sessionClientId)
        .toList()
      ..sort((a, b) => a.performedAt.compareTo(b.performedAt));
    return applyRevisions(rows);
  }

  @override
  Future<void> clear() async {
    _today.clear();
    _queue.clear();
    _sessions.clear();
    _logs.clear();
  }

  @override
  Future<void> close() async {}
}

class _QueuedEvent {
  _QueuedEvent(this.studentId, this.event, this.seq);

  final String studentId;
  final WorkoutEvent event;
  final int seq;
  int attempts = 0;
}

class _StoredSession {
  const _StoredSession(this.studentId, this.session);

  final String studentId;
  final LocalSession session;
}
