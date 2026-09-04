import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/evolution_repository.dart';
import '../domain/bioimpedance.dart';

class BioimpedanceListState {
  const BioimpedanceListState({this.items = const [], this.hasMore = false});

  final List<BioimpedanceRecord> items;
  final bool hasMore;
}

/// Lista paginada de leituras de bioimpedância do próprio aluno — mesmo
/// desenho do [MeasurementsController].
class BioimpedanceController
    extends AutoDisposeAsyncNotifier<BioimpedanceListState> {
  String? _cursor;

  @override
  Future<BioimpedanceListState> build() async {
    final page =
        await ref.watch(evolutionRepositoryProvider).listBioimpedance();
    _cursor = page.nextCursor;
    return BioimpedanceListState(items: page.items, hasMore: page.hasMore);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;

    final page = await ref
        .read(evolutionRepositoryProvider)
        .listBioimpedance(cursor: _cursor);
    _cursor = page.nextCursor;
    state = AsyncData(
      BioimpedanceListState(
        items: [...current.items, ...page.items],
        hasMore: page.hasMore,
      ),
    );
  }

  Future<void> create(BioimpedanceDraft draft) async {
    await ref.read(evolutionRepositoryProvider).createBioimpedance(draft);
    ref.invalidateSelf();
    await future;
  }

  Future<void> delete(String id) async {
    await ref.read(evolutionRepositoryProvider).deleteBioimpedance(id);
    ref.invalidateSelf();
    await future;
  }
}

final bioimpedanceProvider = AsyncNotifierProvider.autoDispose<
    BioimpedanceController, BioimpedanceListState>(
  BioimpedanceController.new,
);
