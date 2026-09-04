import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/evolution_repository.dart';
import '../domain/measurement.dart';

/// Estado da lista de medidas: a página acumulada mais a marca de que há
/// mais itens (mesmo formato do `LibraryState`, P1.6).
class MeasurementListState {
  const MeasurementListState({this.items = const [], this.hasMore = false});

  final List<BodyMeasurement> items;
  final bool hasMore;
}

/// Lista paginada de medidas corporais do próprio aluno, mais recente
/// primeiro (cursor keyset do `assessment`, P2.3).
class MeasurementsController
    extends AutoDisposeAsyncNotifier<MeasurementListState> {
  String? _cursor;

  @override
  Future<MeasurementListState> build() async {
    final page =
        await ref.watch(evolutionRepositoryProvider).listMeasurements();
    _cursor = page.nextCursor;
    return MeasurementListState(items: page.items, hasMore: page.hasMore);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;

    final page = await ref
        .read(evolutionRepositoryProvider)
        .listMeasurements(cursor: _cursor);
    _cursor = page.nextCursor;
    state = AsyncData(
      MeasurementListState(
        items: [...current.items, ...page.items],
        hasMore: page.hasMore,
      ),
    );
  }

  /// Lança uma medida e recarrega a lista — o novo registro é o mais
  /// recente, então entra sempre no topo.
  Future<void> create(MeasurementDraft draft) async {
    await ref.read(evolutionRepositoryProvider).createMeasurement(draft);
    ref.invalidateSelf();
    await future;
  }

  Future<void> delete(String id) async {
    await ref.read(evolutionRepositoryProvider).deleteMeasurement(id);
    ref.invalidateSelf();
    await future;
  }
}

final measurementsProvider = AsyncNotifierProvider.autoDispose<
    MeasurementsController, MeasurementListState>(
  MeasurementsController.new,
);
