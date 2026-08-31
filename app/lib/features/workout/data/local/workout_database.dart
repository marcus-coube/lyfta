import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/workout_event.dart';
import 'workout_local_store.dart';

part 'workout_database.g.dart';

/// Cache do `GET /v1/me/today` — uma linha por aluno, o payload inteiro em
/// JSON. Guardar o payload cru (e não a árvore normalizada) é deliberado: o
/// contrato do P1.5 foi desenhado para ser cacheado integralmente, e
/// normalizar aqui só criaria um segundo modelo para manter em dia.
class TodayCache extends Table {
  TextColumn get studentId => text()();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {studentId};
}

/// Fila de saída (ADR-003 §4): append-only, drenada em lote pelo worker.
class PendingEventRows extends Table {
  TextColumn get clientId => text()();
  TextColumn get studentId => text()();
  TextColumn get type => text()();
  TextColumn get payload => text()();
  DateTimeColumn get performedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {clientId};
}

/// Sessão de treino do device. Vive antes de existir no servidor — é o que
/// permite começar o treino em modo avião.
class LocalSessionRows extends Table {
  TextColumn get clientId => text()();
  TextColumn get studentId => text()();
  TextColumn get dayId => text()();
  TextColumn get dayLabel => text()();
  TextColumn get dayTitle => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {clientId};
}

/// Séries registradas no device. Espelha `workout_set_logs` e é igualmente
/// **append-only**: corrigir insere outra linha com `revises` preenchido.
class LocalSetLogRows extends Table {
  TextColumn get clientId => text()();
  TextColumn get studentId => text()();
  TextColumn get sessionClientId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get setNo => integer()();
  IntColumn get repsDone => integer().nullable()();
  RealColumn get loadKg => real().nullable()();
  RealColumn get rpe => real().nullable()();
  DateTimeColumn get performedAt => dateTime()();
  TextColumn get revises => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {clientId};
}

@DriftDatabase(
  tables: [TodayCache, PendingEventRows, LocalSessionRows, LocalSetLogRows],
)
class WorkoutDatabase extends _$WorkoutDatabase {
  WorkoutDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}

/// Implementação persistente do [WorkoutLocalStore] — SQLite via Drift,
/// como manda o ADR-003 §3.
class DriftWorkoutStore implements WorkoutLocalStore {
  DriftWorkoutStore(this.db);

  final WorkoutDatabase db;

  @override
  Future<void> saveToday(String studentId, String payload) {
    return db.into(db.todayCache).insertOnConflictUpdate(
          TodayCacheCompanion.insert(
            studentId: studentId,
            payload: payload,
            fetchedAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<CachedToday?> readToday(String studentId) async {
    final row = await (db.select(db.todayCache)
          ..where((t) => t.studentId.equals(studentId)))
        .getSingleOrNull();
    if (row == null) return null;
    return CachedToday(payload: row.payload, fetchedAt: row.fetchedAt);
  }

  @override
  Future<void> enqueue(String studentId, WorkoutEvent event) {
    return db.into(db.pendingEventRows).insert(
          PendingEventRowsCompanion.insert(
            clientId: event.clientId,
            studentId: studentId,
            type: event.type.code,
            payload: event.encodePayload(),
            performedAt: event.performedAt,
            createdAt: DateTime.now(),
          ),
          // Reenfileirar o mesmo fato não é erro nem duplicata: a fila tem a
          // mesma idempotência por `client_id` que o servidor.
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<List<PendingEvent>> pending(String studentId, {int limit = 200}) async {
    final rows = await (db.select(db.pendingEventRows)
          ..where((t) => t.studentId.equals(studentId))
          // Desempate pelo `client_id`: o UUID v7 é ordenável no tempo, então
          // dois eventos criados no mesmo milissegundo continuam saindo na
          // ordem em que aconteceram — `session_start` antes do `set_log`.
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.clientId),
          ])
          ..limit(limit))
        .get();
    return rows.map(_toPendingEvent).toList();
  }

  @override
  Future<int> pendingCount(String studentId) async {
    final count = db.pendingEventRows.clientId.count();
    final row = await (db.selectOnly(db.pendingEventRows)
          ..addColumns([count])
          ..where(db.pendingEventRows.studentId.equals(studentId)))
        .getSingle();
    return row.read(count) ?? 0;
  }

  @override
  Future<void> removePending(List<String> clientIds) async {
    if (clientIds.isEmpty) return;
    await (db.delete(db.pendingEventRows)
          ..where((t) => t.clientId.isIn(clientIds)))
        .go();
  }

  @override
  Future<void> registerAttempt(List<String> clientIds) async {
    if (clientIds.isEmpty) return;
    await (db.update(db.pendingEventRows)
          ..where((t) => t.clientId.isIn(clientIds)))
        .write(
      PendingEventRowsCompanion.custom(
        attempts: db.pendingEventRows.attempts + const Constant(1),
      ),
    );
  }

  @override
  Future<void> saveSession(String studentId, LocalSession session) {
    return db.into(db.localSessionRows).insertOnConflictUpdate(
          LocalSessionRowsCompanion.insert(
            clientId: session.clientId,
            studentId: studentId,
            dayId: session.dayId,
            dayLabel: session.dayLabel,
            dayTitle: session.dayTitle,
            startedAt: session.startedAt,
            finishedAt: Value(session.finishedAt),
          ),
        );
  }

  @override
  Future<LocalSession?> openSession(String studentId) async {
    final row = await (db.select(db.localSessionRows)
          ..where((t) => t.studentId.equals(studentId) & t.finishedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return LocalSession(
      clientId: row.clientId,
      dayId: row.dayId,
      dayLabel: row.dayLabel,
      dayTitle: row.dayTitle,
      startedAt: row.startedAt,
    );
  }

  @override
  Future<void> finishSession(String clientId, DateTime finishedAt) async {
    await (db.update(db.localSessionRows)
          ..where((t) => t.clientId.equals(clientId)))
        .write(LocalSessionRowsCompanion(finishedAt: Value(finishedAt)));
  }

  @override
  Future<void> saveSetLog(String studentId, LocalSetLog log) {
    return db.into(db.localSetLogRows).insert(
          LocalSetLogRowsCompanion.insert(
            clientId: log.clientId,
            studentId: studentId,
            sessionClientId: log.sessionClientId,
            exerciseId: log.exerciseId,
            setNo: log.setNo,
            repsDone: Value(log.repsDone),
            loadKg: Value(log.loadKg),
            rpe: Value(log.rpe),
            performedAt: log.performedAt,
            revises: Value(log.revises),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<List<LocalSetLog>> setLogs(String sessionClientId) async {
    final rows = await (db.select(db.localSetLogRows)
          ..where((t) => t.sessionClientId.equals(sessionClientId))
          ..orderBy([(t) => OrderingTerm.asc(t.performedAt)]))
        .get();
    return applyRevisions(rows.map(_toSetLog).toList());
  }

  @override
  Future<void> clear() async {
    await db.batch((batch) {
      batch
        ..deleteAll(db.todayCache)
        ..deleteAll(db.pendingEventRows)
        ..deleteAll(db.localSessionRows)
        ..deleteAll(db.localSetLogRows);
    });
  }

  @override
  Future<void> close() => db.close();

  PendingEvent _toPendingEvent(PendingEventRow row) {
    return PendingEvent(
      attempts: row.attempts,
      event: WorkoutEvent(
        clientId: row.clientId,
        type: WorkoutEventType.fromCode(row.type),
        performedAt: row.performedAt,
        payload: jsonDecode(row.payload) as Map<String, dynamic>,
      ),
    );
  }

  LocalSetLog _toSetLog(LocalSetLogRow row) {
    return LocalSetLog(
      clientId: row.clientId,
      sessionClientId: row.sessionClientId,
      exerciseId: row.exerciseId,
      setNo: row.setNo,
      repsDone: row.repsDone,
      loadKg: row.loadKg,
      rpe: row.rpe,
      performedAt: row.performedAt,
      revises: row.revises,
    );
  }
}
