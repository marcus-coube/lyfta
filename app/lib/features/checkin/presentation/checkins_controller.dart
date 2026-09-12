import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/comms_socket_provider.dart';
import '../data/checkin_event.dart';
import '../data/checkin_repository.dart';
import '../domain/checkin.dart';

/// Fila de check-ins de um aluno, do ponto de vista do coach (P3.3/P3.5
/// §3) — não revisados primeiro, cronológico depois (ordenação já vem do
/// servidor). Recarrega sozinha quando chega `checkin.pain_strong` pelo WS
/// para este aluno.
class CheckinListState {
  const CheckinListState({this.items = const [], this.hasMore = false});

  final List<WorkoutCheckin> items;
  final bool hasMore;

  int get pendingCount => items.where((c) => !c.isReviewed).length;
}

class CheckinsController
    extends AutoDisposeFamilyAsyncNotifier<CheckinListState, String> {
  String? _cursor;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  Future<CheckinListState> build(String studentId) async {
    final socket = ref.watch(commsSocketProvider);
    _sub = socket.events.listen((json) {
      final event = CheckinPainStrongEvent.fromJson(json);
      if (event != null && event.studentId == studentId) {
        unawaited(refresh());
      }
    });
    ref.onDispose(() => _sub?.cancel());

    final page =
        await ref.read(checkinRepositoryProvider).list(studentId: studentId, limit: 30);
    _cursor = page.nextCursor;
    return CheckinListState(items: page.items, hasMore: page.hasMore);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;
    final page = await ref
        .read(checkinRepositoryProvider)
        .list(studentId: arg, cursor: _cursor, limit: 30);
    _cursor = page.nextCursor;
    state = AsyncData(
      CheckinListState(
        items: [...current.items, ...page.items],
        hasMore: page.hasMore,
      ),
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> review(String id) async {
    final updated = await ref.read(checkinRepositoryProvider).review(id);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      CheckinListState(
        items: [for (final c in current.items) c.id == id ? updated : c],
        hasMore: current.hasMore,
      ),
    );
  }
}

final checkinsProvider = AsyncNotifierProvider.autoDispose
    .family<CheckinsController, CheckinListState, String>(
  CheckinsController.new,
);
