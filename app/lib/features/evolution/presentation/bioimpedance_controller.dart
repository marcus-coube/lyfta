import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/evolution_repository.dart';
import '../domain/bioimpedance.dart';
import '../domain/evolution_scope.dart';

class BioimpedanceListState {
  const BioimpedanceListState({this.items = const [], this.hasMore = false});

  final List<BioimpedanceRecord> items;
  final bool hasMore;
}

/// Lista paginada de leituras de bioimpedância — mesmo desenho do
/// [MeasurementsController], inclusive o escopo como argumento da família.
class BioimpedanceController extends AutoDisposeFamilyAsyncNotifier<
    BioimpedanceListState, EvolutionScope> {
  String? _cursor;

  @override
  Future<BioimpedanceListState> build(EvolutionScope scope) async {
    final page =
        await ref.watch(evolutionRepositoryProvider).listBioimpedance(scope);
    _cursor = page.nextCursor;
    return BioimpedanceListState(items: page.items, hasMore: page.hasMore);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;

    final page = await ref
        .read(evolutionRepositoryProvider)
        .listBioimpedance(arg, cursor: _cursor);
    _cursor = page.nextCursor;
    state = AsyncData(
      BioimpedanceListState(
        items: [...current.items, ...page.items],
        hasMore: page.hasMore,
      ),
    );
  }

  Future<void> create(BioimpedanceDraft draft) async {
    await ref.read(evolutionRepositoryProvider).createBioimpedance(arg, draft);
    ref.invalidateSelf();
    await future;
  }

  Future<void> delete(String id) async {
    await ref.read(evolutionRepositoryProvider).deleteBioimpedance(arg, id);
    ref.invalidateSelf();
    await future;
  }
}

final bioimpedanceProvider = AsyncNotifierProvider.autoDispose.family<
    BioimpedanceController, BioimpedanceListState, EvolutionScope>(
  BioimpedanceController.new,
);
