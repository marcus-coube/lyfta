import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../data/session_media_repository.dart';
import '../domain/session_media.dart';

/// Páginas de mídia lidas de uma vez para casar com os cards e o detalhe do
/// treino (o servidor não filtra por sessão): 3 x 100 cobre meses de treino
/// de um aluno (no máximo 3 mídias por sessão).
const int coachMediaPageSize = 100;
const int coachMediaMaxPages = 3;

/// Mídia de execução de um aluno vista pelo professor (ADR-020, P12.3).
///
/// - [pending]: `GET /v1/session-media?student_id=&pending=true` — alimenta a
///   seção "Para avaliar" (independe de check-in), com cursor próprio;
/// - [all]: `GET /v1/session-media?student_id=` — alimenta o card e o detalhe
///   (agrupado por sessão), incluindo as já vistas e as expiradas.
class CoachMediaState {
  const CoachMediaState({
    this.pending = const [],
    this.pendingHasMore = false,
    this.all = const [],
  });

  final List<SessionMedia> pending;
  final bool pendingHasMore;
  final List<SessionMedia> all;

  List<SessionMedia> forSession(String sessionClientId) => [
        for (final m in all)
          if (m.sessionClientId == sessionClientId) m,
      ];
}

class CoachMediaController
    extends AutoDisposeFamilyAsyncNotifier<CoachMediaState, String> {
  String? _pendingCursor;
  bool _loadingMore = false;

  @override
  Future<CoachMediaState> build(String studentId) async {
    final repo = ref.read(sessionMediaRepositoryProvider);
    final pendingPage = await repo.listForCoach(
      studentId: studentId,
      pendingOnly: true,
      limit: coachMediaPageSize,
    );
    _pendingCursor = pendingPage.nextCursor;

    final all = <SessionMedia>[];
    String? cursor;
    for (var page = 0; page < coachMediaMaxPages; page++) {
      final result = await repo.listForCoach(
        studentId: studentId,
        cursor: cursor,
        limit: coachMediaPageSize,
      );
      all.addAll(result.items);
      cursor = result.nextCursor;
      if (cursor == null) break;
    }
    return CoachMediaState(
      pending: pendingPage.items,
      pendingHasMore: pendingPage.hasMore,
      all: all,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Próxima página de "Para avaliar"; falha mantém a lista.
  Future<void> loadMorePending() async {
    final current = state.valueOrNull;
    if (current == null || !current.pendingHasMore || _loadingMore) return;
    _loadingMore = true;
    try {
      final page = await ref.read(sessionMediaRepositoryProvider).listForCoach(
            studentId: arg,
            pendingOnly: true,
            cursor: _pendingCursor,
            limit: coachMediaPageSize,
          );
      _pendingCursor = page.nextCursor;
      state = AsyncData(
        CoachMediaState(
          pending: [...current.pending, ...page.items],
          pendingHasMore: page.hasMore,
          all: current.all,
        ),
      );
    } on ApiException {
      // Mantém o que já está na tela.
    } finally {
      _loadingMore = false;
    }
  }

  /// Ciência (com resposta opcional). Devolve a mídia atualizada, já com a
  /// data de exclusão de 7 dias, e tira o item de "Para avaliar".
  Future<SessionMedia> ack(String id, {String? feedback}) async {
    final updated = await ref
        .read(sessionMediaRepositoryProvider)
        .ack(id, feedback: feedback);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(
        CoachMediaState(
          pending: [
            for (final m in current.pending)
              if (m.id != id) m,
          ],
          pendingHasMore: current.pendingHasMore,
          all: [
            for (final m in current.all)
              if (m.id == id) _keepUrl(updated, m) else m,
          ],
        ),
      );
    }
    return updated;
  }

  SessionMedia _keepUrl(SessionMedia updated, SessionMedia old) =>
      updated.mediaUrl != null ? updated : old.withAck(updated);
}

final coachMediaProvider = AsyncNotifierProvider.autoDispose
    .family<CoachMediaController, CoachMediaState, String>(
  CoachMediaController.new,
);
