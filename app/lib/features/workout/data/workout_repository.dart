import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/http/api_exception.dart';
import '../domain/today.dart';
import '../domain/workout_event.dart';
import 'local/workout_store.dart';
import 'workout_api.dart';

/// UUID v7 para os `client_id` da fila: é ordenável no tempo, então a ordem
/// de inserção continua legível no banco do servidor mesmo quando o lote
/// chega dias depois (ADR-003 §2).
const _uuid = Uuid();

String newClientId() => _uuid.v7();

/// Store local vivo enquanto o app viver — abrir o SQLite a cada leitura
/// custaria caro e perderia a sessão aberta.
final workoutLocalStoreProvider = Provider<WorkoutLocalStore>((ref) {
  final store = openWorkoutStore();
  ref.onDispose(store.close);
  return store;
});

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepository(
    store: ref.watch(workoutLocalStoreProvider),
    api: ref.watch(workoutApiProvider),
  );
});

/// O treino do dia como a tela o consome: o conteúdo, quando foi baixado e
/// se a última tentativa de atualizar falhou por falta de rede.
class TodayView {
  const TodayView({
    required this.today,
    required this.fetchedAt,
    this.stale = false,
    this.finishedLocally = false,
  });

  final Today today;
  final DateTime fetchedAt;

  /// `true` quando o que está na tela veio do cache porque a rede falhou —
  /// é o que acende o aviso discreto de offline.
  final bool stale;

  /// O treino do cache já foi concluído no aparelho (offline) e a fila ainda
  /// não chegou ao servidor: a tela não oferece repeti-lo (E2E P4.4).
  final bool finishedLocally;
}

/// Repositório offline-first da execução (ADR-003 §1).
///
/// **A UI lê sempre do banco local.** A rede só faz duas coisas: hidratar o
/// cache do treino do dia e despachar a fila. Nenhum método aqui falha por
/// falta de conexão — quem trata rede é o worker de sync.
class WorkoutRepository {
  WorkoutRepository({required WorkoutLocalStore store, required WorkoutApi api})
      : _store = store,
        _api = api;

  final WorkoutLocalStore _store;
  final WorkoutApi _api;

  /// Lê do cache e, se houver rede, atualiza. Sem cache e sem rede, a
  /// exceção sobe: não há o que desenhar.
  Future<TodayView> load(String studentId, {bool refresh = true}) async {
    final cached = await _store.readToday(studentId);
    if (cached == null) return _fetch(studentId);
    if (!refresh) return _fromCache(studentId, cached, stale: false);
    try {
      return await _fetch(studentId);
    } on ApiException {
      // Com treino baixado, falha de rede não é erro de tela: é offline.
      return _fromCache(studentId, cached, stale: true);
    }
  }

  Future<TodayView> _fromCache(
    String studentId,
    CachedToday cached, {
    required bool stale,
  }) async {
    final today = Today.decode(cached.payload);
    final dayId = today.day?.id;
    final finished = dayId != null &&
        await _store.finishedDaySince(studentId, dayId, cached.fetchedAt);
    return TodayView(
      today: today,
      fetchedAt: cached.fetchedAt,
      stale: stale,
      finishedLocally: finished,
    );
  }

  Future<TodayView> _fetch(String studentId) async {
    final payload = await _api.today();
    final encoded = jsonEncode(payload);
    await _store.saveToday(studentId, encoded);
    return TodayView(today: Today.fromJson(payload), fetchedAt: DateTime.now());
  }

  /// Troca o treino de hoje e rebaixa o payload já com o dia novo (P1.8).
  ///
  /// A exceção de rede **sobe**, ao contrário do resto deste repositório: sem
  /// servidor não há como mudar a rotação, e engolir o erro deixaria a tela
  /// mostrando o dia velho como se a troca tivesse valido.
  Future<TodayView> overrideDay(String studentId, String dayId) async {
    await _api.overrideDay(dayId);
    return _fetch(studentId);
  }

  Future<LocalSession?> openSession(String studentId) =>
      _store.openSession(studentId);

  Future<List<LocalSetLog>> setLogs(String sessionClientId) =>
      _store.setLogs(sessionClientId);

  Future<int> pendingCount(String studentId) => _store.pendingCount(studentId);

  /// Começa o treino: a sessão nasce **local** e o `session_start` entra na
  /// fila. Em modo avião os dois acontecem igual.
  Future<LocalSession> startSession({
    required String studentId,
    required String dayId,
    required String dayLabel,
    required String dayTitle,
  }) async {
    final session = LocalSession(
      clientId: newClientId(),
      dayId: dayId,
      dayLabel: dayLabel,
      dayTitle: dayTitle,
      startedAt: DateTime.now(),
    );
    await _store.saveSession(studentId, session);
    await _store.enqueue(
      studentId,
      WorkoutEvent(
        clientId: session.clientId,
        type: WorkoutEventType.sessionStart,
        performedAt: session.startedAt,
        payload: {'day_id': dayId},
      ),
    );
    return session;
  }

  /// Registra uma série executada. [revises] preenchido transforma o fato em
  /// correção (ADR-003 §5): o log antigo continua gravado, some da leitura.
  Future<LocalSetLog> logSet({
    required String studentId,
    required String sessionClientId,
    required String exerciseId,
    required int setNo,
    int? repsDone,
    double? loadKg,
    double? rpe,
    String? revises,
  }) async {
    final log = LocalSetLog(
      clientId: newClientId(),
      sessionClientId: sessionClientId,
      exerciseId: exerciseId,
      setNo: setNo,
      performedAt: DateTime.now(),
      repsDone: repsDone,
      loadKg: loadKg,
      rpe: rpe,
      revises: revises,
    );
    await _store.saveSetLog(studentId, log);
    await _store.enqueue(
      studentId,
      WorkoutEvent(
        clientId: log.clientId,
        type: revises == null
            ? WorkoutEventType.setLog
            : WorkoutEventType.setRevision,
        performedAt: log.performedAt,
        payload: {
          'session_client_id': sessionClientId,
          'exercise_id': exerciseId,
          'set_no': setNo,
          'reps_done': repsDone,
          'load_kg': loadKg,
          'rpe': rpe,
          if (revises != null) 'revises': revises,
        },
      ),
    );
    return log;
  }

  /// Fecha o treino. O servidor só avança a rotação A→B com pelo menos uma
  /// série registrada (P1.5) — abrir e desistir não gasta o dia.
  Future<void> finishSession({
    required String studentId,
    required String sessionClientId,
  }) async {
    final finishedAt = DateTime.now();
    await _store.finishSession(sessionClientId, finishedAt);
    await _store.enqueue(
      studentId,
      WorkoutEvent(
        clientId: newClientId(),
        type: WorkoutEventType.sessionFinish,
        performedAt: finishedAt,
        payload: {'session_client_id': sessionClientId},
      ),
    );
  }

  /// Drena a fila num lote só. Devolve quantos eventos saíram da fila;
  /// falha de rede sobe como [ApiException] e a fila fica intacta.
  Future<int> drainOnce(String studentId, {int limit = 100}) async {
    final pending = await _store.pending(studentId, limit: limit);
    if (pending.isEmpty) return 0;

    final events = pending.map((p) => p.event).toList();
    final ids = events.map((e) => e.clientId).toList();
    final SyncResult result;
    try {
      result = await _api.pushLogs(events);
    } on ApiException {
      await _store.registerAttempt(ids);
      rethrow;
    }

    // Sai da fila tudo que o servidor viu — inclusive o que ele recusou por
    // conteúdo: recusa não muda em retentativa, e mantê-la travaria a fila.
    final settled = result.outcomes.map((o) => o.clientId).toSet();
    await _store.removePending(
      ids.where(settled.contains).toList(),
    );
    return settled.length;
  }

  /// Troca de usuário no mesmo device não pode misturar execução de duas
  /// pessoas — o `AuthController` chama isto no logout.
  Future<void> clearLocal() => _store.clear();
}
