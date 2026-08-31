import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/features/workout/data/local/workout_database.dart';
import 'package:lyfta/features/workout/data/workout_api.dart';
import 'package:lyfta/features/workout/data/workout_repository.dart';
import 'package:lyfta/features/workout/domain/workout_event.dart';

/// Servidor de mentira com a semântica do P1.5: idempotência por
/// `client_id`, e cada evento com o próprio desfecho.
class _FakeApi extends WorkoutApi {
  _FakeApi() : super(Dio());

  final List<List<WorkoutEvent>> batches = [];
  final Set<String> _seen = {};
  Set<String> rejects = {};
  bool offline = false;

  @override
  Future<Map<String, dynamic>> today() async {
    if (offline) throw const ApiException.network();
    return {
      'status': 'no_plan',
      'previous_loads': <dynamic>[],
      'recent_sessions': <dynamic>[],
    };
  }

  @override
  Future<SyncResult> pushLogs(List<WorkoutEvent> events) async {
    if (offline) throw const ApiException.network();
    batches.add(events);
    var accepted = 0;
    var duplicates = 0;
    var rejected = 0;
    final outcomes = <SyncOutcome>[];
    for (final event in events) {
      if (rejects.contains(event.clientId)) {
        rejected++;
        outcomes.add(
          SyncOutcome(
            clientId: event.clientId,
            status: 'rejected',
            code: 'invalid_event',
          ),
        );
        continue;
      }
      if (!_seen.add(event.clientId)) {
        duplicates++;
        outcomes.add(
          SyncOutcome(clientId: event.clientId, status: 'duplicate'),
        );
        continue;
      }
      accepted++;
      outcomes.add(SyncOutcome(clientId: event.clientId, status: 'accepted'));
    }
    return SyncResult(
      outcomes: outcomes,
      accepted: accepted,
      duplicates: duplicates,
      rejected: rejected,
    );
  }
}

void main() {
  const studentId = 'student-1';
  const exerciseId = '3f7c1d0e-0000-4000-8000-000000000001';

  late DriftWorkoutStore store;
  late _FakeApi api;
  late WorkoutRepository repo;

  setUp(() {
    store = DriftWorkoutStore(WorkoutDatabase(NativeDatabase.memory()));
    api = _FakeApi();
    repo = WorkoutRepository(store: store, api: api);
  });

  tearDown(() => store.close());

  Future<String> startAndLogTwoSets() async {
    final session = await repo.startSession(
      studentId: studentId,
      dayId: 'day-a',
      dayLabel: 'A',
      dayTitle: 'Peito',
    );
    await repo.logSet(
      studentId: studentId,
      sessionClientId: session.clientId,
      exerciseId: exerciseId,
      setNo: 1,
      repsDone: 10,
      loadKg: 40,
    );
    await repo.logSet(
      studentId: studentId,
      sessionClientId: session.clientId,
      exerciseId: exerciseId,
      setNo: 2,
      repsDone: 8,
      loadKg: 45,
    );
    return session.clientId;
  }

  test('a fila sai na ordem em que os fatos aconteceram', () async {
    final sessionId = await startAndLogTwoSets();
    await repo.finishSession(studentId: studentId, sessionClientId: sessionId);

    final pending = await store.pending(studentId);
    expect(
      pending.map((p) => p.event.type),
      [
        WorkoutEventType.sessionStart,
        WorkoutEventType.setLog,
        WorkoutEventType.setLog,
        WorkoutEventType.sessionFinish,
      ],
    );
  });

  test('drenar esvazia a fila e manda tudo num lote só', () async {
    await startAndLogTwoSets();

    expect(await repo.drainOnce(studentId), 3);
    expect(await repo.pendingCount(studentId), 0);
    expect(api.batches, hasLength(1));
    expect(api.batches.single, hasLength(3));
  });

  test('sem rede a fila fica intacta e a tentativa é contada', () async {
    await startAndLogTwoSets();
    api.offline = true;

    await expectLater(repo.drainOnce(studentId), throwsA(isA<ApiException>()));
    expect(await repo.pendingCount(studentId), 3);
    final pending = await store.pending(studentId);
    expect(pending.every((p) => p.attempts == 1), isTrue);

    // Rede de volta: o mesmo lote sai inteiro, agora aceito.
    api.offline = false;
    expect(await repo.drainOnce(studentId), 3);
    expect(await repo.pendingCount(studentId), 0);
  });

  test('reenviar o mesmo lote não duplica nada no servidor', () async {
    final sessionId = await startAndLogTwoSets();
    await repo.drainOnce(studentId);

    // O device reenfileira o que já mandou (cenário do ADR-003: resposta
    // perdida na volta). O servidor responde `duplicate` e a fila esvazia.
    await repo.finishSession(studentId: studentId, sessionClientId: sessionId);
    for (final event in api.batches.first) {
      await store.enqueue(studentId, event);
    }

    expect(await repo.drainOnce(studentId), 4);
    expect(await repo.pendingCount(studentId), 0);
    final second = api.batches.last;
    expect(second, hasLength(4));
  });

  test('enfileirar o mesmo client_id duas vezes não duplica a fila', () async {
    final event = WorkoutEvent(
      clientId: newClientId(),
      type: WorkoutEventType.sessionStart,
      performedAt: DateTime.now(),
      payload: const {'day_id': 'day-a'},
    );
    await store.enqueue(studentId, event);
    await store.enqueue(studentId, event);

    expect(await repo.pendingCount(studentId), 1);
  });

  test('evento recusado por conteúdo também sai da fila', () async {
    await startAndLogTwoSets();
    final pending = await store.pending(studentId);
    api.rejects = {pending[1].event.clientId};

    // Sem isto a fila travaria para sempre reenviando o mesmo evento ruim.
    expect(await repo.drainOnce(studentId), 3);
    expect(await repo.pendingCount(studentId), 0);
  });

  test('correção esconde o log original sem apagar o fato', () async {
    final sessionId = await startAndLogTwoSets();
    final original = (await repo.setLogs(sessionId)).first;

    await repo.logSet(
      studentId: studentId,
      sessionClientId: sessionId,
      exerciseId: exerciseId,
      setNo: 1,
      repsDone: 12,
      loadKg: 42.5,
      revises: original.clientId,
    );

    final logs = await repo.setLogs(sessionId);
    expect(logs, hasLength(2));
    expect(logs.any((l) => l.clientId == original.clientId), isFalse);
    expect(logs.firstWhere((l) => l.setNo == 1).loadKg, 42.5);

    // O fato antigo continua gravado — append-only (ADR-003 §2).
    final raw = await store.db.select(store.db.localSetLogRows).get();
    expect(raw, hasLength(3));

    // E a correção viaja como `set_revision`, não como update.
    final pending = await store.pending(studentId);
    expect(pending.last.event.type, WorkoutEventType.setRevision);
    expect(pending.last.event.payload['revises'], original.clientId);
  });
}
