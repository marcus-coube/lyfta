import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/features/workout/data/local/memory_workout_store.dart';
import 'package:lyfta/features/workout/data/sync_worker.dart';
import 'package:lyfta/features/workout/data/workout_api.dart';
import 'package:lyfta/features/workout/data/workout_repository.dart';
import 'package:lyfta/features/workout/domain/today.dart';
import 'package:lyfta/features/workout/presentation/today_controller.dart';

/// Payload de `/v1/me/today` com o dia [label] — só o que a tela lê.
Map<String, dynamic> _todayPayload(String label) => {
      'status': 'ready',
      'plan': {'id': 'p1', 'title': 'Plano', 'version_id': 'v1', 'version_no': 1},
      'day': {
        'id': 'day-$label',
        'label': label,
        'title': '',
        'blocks': <Map<String, dynamic>>[],
      },
      'rotation': [
        {'id': 'day-A', 'label': 'A', 'position': 0},
        {'id': 'day-B', 'label': 'B', 'position': 1},
      ],
      'next_day_id': label == 'A' ? 'day-B' : 'day-A',
      'previous_loads': <Map<String, dynamic>>[],
      'recent_sessions': <Map<String, dynamic>>[],
    };

/// Repositório falso: o servidor entrega o dia A enquanto houver fila, e o B
/// depois que ela drena — é o que acontece de verdade, porque o
/// `session_finish` avança a rotação no servidor (ADR-004 §3).
class _FakeRepository extends WorkoutRepository {
  _FakeRepository()
      : super(store: MemoryWorkoutStore(), api: WorkoutApi(Dio()));

  int pending = 5;
  int loads = 0;

  @override
  Future<TodayView> load(String studentId, {bool refresh = true}) async {
    loads++;
    return TodayView(
      today: Today.fromJson(_todayPayload(pending > 0 ? 'A' : 'B')),
      fetchedAt: DateTime(2026, 9, 2),
    );
  }

  @override
  Future<int> drainOnce(String studentId, {int limit = 100}) async {
    if (pending == 0) return 0;
    final sent = pending;
    pending = 0;
    return sent;
  }

  @override
  Future<int> pendingCount(String studentId) async => pending;
}

/// Controller de auth fixo: o worker e a tela só precisam do `userId`.
class _FakeAuthController extends AuthController {
  @override
  AuthState build() => AuthState.authenticated(
        roles: {UserRole.student},
        tenantId: 'tenant-1',
        userId: 'student-1',
      );
}

void main() {
  // O worker assina `connectivity_plus` (EventChannel) no build; sem binding
  // a assinatura estoura antes de virar o MissingPluginException que ele
  // trata.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('drenar a fila recarrega o treino do dia', () async {
    final repo = _FakeRepository();
    final container = ProviderContainer(
      overrides: [
        workoutRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(_FakeAuthController.new),
      ],
    );
    addTearDown(container.dispose);

    // Primeira leitura: ainda há fila, então o servidor devolve o dia A.
    final first = await container.read(todayControllerProvider.future);
    expect(first.today.day?.label, 'A');
    final loadsBefore = repo.loads;

    await container.read(syncWorkerProvider.notifier).sync();
    // O refresh é disparado por listener, não pelo await do sync.
    await Future<void>.delayed(Duration.zero);
    final after = await container.read(todayControllerProvider.future);

    // Sem isso o aluno volta do modo avião e continua vendo — e podendo
    // repetir — o treino que acabou de fazer.
    expect(after.today.day?.label, 'B');
    expect(repo.loads, greaterThan(loadsBefore));
  });

  test('sync sem nada na fila não recarrega a tela à toa', () async {
    final repo = _FakeRepository()..pending = 0;
    final container = ProviderContainer(
      overrides: [
        workoutRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(_FakeAuthController.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(todayControllerProvider.future);
    final loadsBefore = repo.loads;

    await container.read(syncWorkerProvider.notifier).sync();
    await Future<void>.delayed(Duration.zero);

    // Recarregar a cada sync vazio gastaria rede do aluno sem motivo — e o
    // worker roda a cada reconexão.
    expect(repo.loads, loadsBefore);
  });
}
