import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/features/workout/data/local/workout_database.dart';
import 'package:lyfta/features/workout/data/workout_api.dart';
import 'package:lyfta/features/workout/data/workout_repository.dart';

/// Servidor que serve o treino A e depois cai (modo avião).
class _FakeApi extends WorkoutApi {
  _FakeApi() : super(Dio());

  bool offline = false;

  @override
  Future<Map<String, dynamic>> today() async {
    if (offline) throw const ApiException.network();
    return {
      'status': 'ready',
      'plan': {
        'id': 'plan-1',
        'title': 'ABC',
        'version_id': 'v1',
        'version_no': 1,
      },
      'day': {
        'id': 'day-a',
        'label': 'A',
        'title': 'Peito',
        'blocks': <dynamic>[],
      },
      'previous_loads': <dynamic>[],
      'recent_sessions': <dynamic>[],
    };
  }
}

void main() {
  const studentId = 'student-1';

  // E2E P4.4: concluído o treino do cache sem rede, Hoje seguia oferecendo
  // o mesmo treino até a fila chegar ao servidor.
  test('treino do cache concluído offline vem marcado como feito', () async {
    final store = DriftWorkoutStore(WorkoutDatabase(NativeDatabase.memory()));
    final api = _FakeApi();
    final repo = WorkoutRepository(store: store, api: api);

    final first = await repo.load(studentId);
    expect(first.finishedLocally, isFalse);

    api.offline = true;
    final session = await repo.startSession(
      studentId: studentId,
      dayId: 'day-a',
      dayLabel: 'A',
      dayTitle: 'Peito',
    );
    var view = await repo.load(studentId);
    expect(view.stale, isTrue);
    expect(view.finishedLocally, isFalse, reason: 'sessão ainda aberta');

    await repo.finishSession(
      studentId: studentId,
      sessionClientId: session.clientId,
    );
    view = await repo.load(studentId);
    expect(view.finishedLocally, isTrue);

    // Com rede, o servidor manda o dia novo e o cache é baixado de novo.
    api.offline = false;
    view = await repo.load(studentId);
    expect(view.finishedLocally, isFalse);
  });
}
