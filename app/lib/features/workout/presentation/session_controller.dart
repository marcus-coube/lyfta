import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../data/sync_worker.dart';
import '../data/workout_repository.dart';
import '../domain/today.dart';
import '../domain/workout_event.dart';

/// Treino em andamento: a sessão do device, o dia que ela congelou e as
/// séries já registradas.
class SessionState {
  const SessionState({
    required this.session,
    required this.today,
    required this.logs,
  });

  final LocalSession session;
  final Today today;

  /// Logs já com as revisões aplicadas: corrigir uma série troca o que a
  /// tela mostra sem apagar o fato antigo (ADR-003 §5).
  final List<LocalSetLog> logs;

  /// A série registrada de um exercício, quando ela já foi feita.
  LocalSetLog? logFor(String exerciseId, int setNo) {
    for (final log in logs) {
      if (log.exerciseId == exerciseId && log.setNo == setNo) return log;
    }
    return null;
  }

  int get completedSets => logs.length;

  double get totalVolumeKg =>
      logs.fold(0, (sum, log) => sum + log.volumeKg);

  Duration get elapsed => DateTime.now().difference(session.startedAt);
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, SessionState?>(
  SessionController.new,
);

/// O player de execução (P1.7 §3).
///
/// Toda ação grava **primeiro** no banco local e só depois pede sincronismo:
/// em modo avião o fluxo é idêntico, o que muda é a fila não drenar.
class SessionController extends AsyncNotifier<SessionState?> {
  @override
  Future<SessionState?> build() async {
    final studentId = ref.watch(authControllerProvider).userId;
    if (studentId == null) return null;

    final repo = ref.read(workoutRepositoryProvider);
    final open = await repo.openSession(studentId);
    if (open == null) return null;

    // Sessão aberta é o aluno que fechou o app no meio do treino: o dia vem
    // do cache, nunca da rede — pode não haver rede nenhuma.
    final cached = await repo.load(studentId, refresh: false);
    return SessionState(
      session: open,
      today: cached.today,
      logs: await repo.setLogs(open.clientId),
    );
  }

  String get _studentId => ref.read(authControllerProvider).userId!;

  /// Começa o treino do dia. Sem dia resolvido não há o que começar.
  Future<void> start(Today today) async {
    final day = today.day;
    if (day == null) return;
    final repo = ref.read(workoutRepositoryProvider);
    final session = await repo.startSession(
      studentId: _studentId,
      dayId: day.id ?? '',
      dayLabel: day.label,
      dayTitle: day.title,
    );
    state = AsyncData(
      SessionState(session: session, today: today, logs: const []),
    );
    _kickSync();
  }

  /// Registra uma série. Com [revises], é correção: um fato novo apontando
  /// para o errado, nunca um update (ADR-003 §5).
  Future<void> logSet({
    required String exerciseId,
    required int setNo,
    int? repsDone,
    double? loadKg,
    String? revises,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final repo = ref.read(workoutRepositoryProvider);
    await repo.logSet(
      studentId: _studentId,
      sessionClientId: current.session.clientId,
      exerciseId: exerciseId,
      setNo: setNo,
      repsDone: repsDone,
      loadKg: loadKg,
      revises: revises,
    );
    state = AsyncData(
      SessionState(
        session: current.session,
        today: current.today,
        logs: await repo.setLogs(current.session.clientId),
      ),
    );
    _kickSync();
  }

  /// Fecha o treino e devolve o resumo para a tela mostrar. A rotação A→B só
  /// anda no servidor, e só com pelo menos uma série (P1.5).
  Future<SessionState?> finish() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    await ref.read(workoutRepositoryProvider).finishSession(
          studentId: _studentId,
          sessionClientId: current.session.clientId,
        );
    state = const AsyncData(null);
    _kickSync();
    return current;
  }

  void _kickSync() {
    unawaited(ref.read(syncWorkerProvider.notifier).sync());
  }
}
