import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/http/api_exception.dart';
import '../data/sync_worker.dart';
import '../data/workout_repository.dart';

final todayControllerProvider =
    AsyncNotifierProvider<TodayController, TodayView>(TodayController.new);

/// Estado da tela Hoje. Lê do banco local e, quando há rede, hidrata —
/// nunca o contrário (ADR-003 §1).
class TodayController extends AsyncNotifier<TodayView> {
  @override
  Future<TodayView> build() async {
    final studentId = ref.watch(authControllerProvider).userId;
    if (studentId == null) throw const ApiException(code: 'unauthenticated');

    // Abrir o app com rede é o momento natural de despachar o que ficou da
    // sessão anterior (ADR-003 §4). Vai em microtask porque um provider não
    // pode alterar o estado de outro durante a própria inicialização.
    unawaited(
      Future.microtask(() => ref.read(syncWorkerProvider.notifier).sync()),
    );
    return ref.read(workoutRepositoryProvider).load(studentId);
  }

  /// Recarrega do servidor. `invalidateSelf` é a forma de um `AsyncNotifier`
  /// refazer o próprio build — chamar `build()` na mão roda `ref.watch` fora
  /// do ciclo do Riverpod e o resultado não chega à tela.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
