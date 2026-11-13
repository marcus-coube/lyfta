import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/coach_session_repository.dart';
import '../domain/coach_session.dart';
import 'checkins_controller.dart';

/// Treino de cada check-in da lista (P11.2 §1): um `lookup` por página de
/// check-ins, em lotes de até [CoachSessionRepository.maxIds].
///
/// - [found]: sessão já no servidor;
/// - sessão ausente do `found` depois de [looked] = "ainda não sincronizada"
///   (fila offline do aluno) — não é erro, e é consultada de novo a cada
///   recarga da lista;
/// - [failed]: o lookup caiu — o card fica sem a linha, com retry. Nunca
///   derruba a lista.
class CoachSessionsState {
  const CoachSessionsState({
    this.found = const {},
    this.looked = const {},
    this.failed = const {},
  });

  final Map<String, CoachSession> found;
  final Set<String> looked;
  final Set<String> failed;

  CoachSessionsState copyWith({
    Map<String, CoachSession>? found,
    Set<String>? looked,
    Set<String>? failed,
  }) {
    return CoachSessionsState(
      found: found ?? this.found,
      looked: looked ?? this.looked,
      failed: failed ?? this.failed,
    );
  }
}

class CoachSessionsController
    extends AutoDisposeFamilyNotifier<CoachSessionsState, String> {
  List<String> _wanted = const [];

  @override
  CoachSessionsState build(String studentId) {
    // Cada vez que a lista muda (primeira página, "carregar mais", refresh,
    // revisão), busca o que ainda não tem sessão.
    ref.listen(
      checkinsProvider(studentId),
      (_, next) {
        final items = next.valueOrNull?.items;
        if (items == null) return;
        _wanted = [for (final c in items) c.sessionClientId];
        // Microtask: durante o `build` o `state` ainda não existe.
        unawaited(Future.microtask(_lookup));
      },
      fireImmediately: true,
    );
    return const CoachSessionsState();
  }

  /// Tenta de novo o que falhou.
  Future<void> retry() => _lookup();

  Future<void> _lookup() async {
    final pending = {
      for (final id in _wanted)
        if (id.isNotEmpty && !state.found.containsKey(id)) id,
    }.toList();
    final repo = ref.read(coachSessionRepositoryProvider);
    for (var i = 0; i < pending.length; i += CoachSessionRepository.maxIds) {
      final chunk = pending.sublist(
        i,
        (i + CoachSessionRepository.maxIds).clamp(0, pending.length),
      );
      try {
        final result = await repo.lookup(arg, chunk);
        state = state.copyWith(
          found: {...state.found, ...result},
          looked: {...state.looked, ...chunk},
          failed: {...state.failed}..removeAll(chunk),
        );
      } on Object {
        state = state.copyWith(failed: {...state.failed, ...chunk});
      }
    }
  }
}

final coachSessionsProvider = NotifierProvider.autoDispose
    .family<CoachSessionsController, CoachSessionsState, String>(
  CoachSessionsController.new,
);

/// Detalhe de uma sessão (P11.2 §2).
typedef CoachSessionKey = ({String studentId, String clientId});

final coachSessionDetailProvider = FutureProvider.autoDispose
    .family<CoachSessionDetail, CoachSessionKey>((ref, key) {
  return ref
      .watch(coachSessionRepositoryProvider)
      .detail(key.studentId, key.clientId);
});
