import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/evolution_repository.dart';
import '../domain/evolution_scope.dart';
import '../domain/measurement.dart';

/// Estado da lista de medidas: a página acumulada mais a marca de que há
/// mais itens (mesmo formato do `LibraryState`, P1.6).
class MeasurementListState {
  const MeasurementListState({this.items = const [], this.hasMore = false});

  final List<BodyMeasurement> items;
  final bool hasMore;
}

/// Lista paginada de medidas corporais, mais recente primeiro (cursor
/// keyset do `assessment`, P2.3).
///
/// O escopo é o argumento da família: `EvolutionScope.me()` na aba do aluno
/// (P2.4) e `EvolutionScope.student(id)` na ficha do coach (P2.5). Cada
/// aluno tem seu próprio estado — abrir a ficha de outro não herda a lista
/// do anterior nem invalida a do coach.
class MeasurementsController extends AutoDisposeFamilyAsyncNotifier<
    MeasurementListState, EvolutionScope> {
  String? _cursor;

  @override
  Future<MeasurementListState> build(EvolutionScope scope) async {
    final page =
        await ref.watch(evolutionRepositoryProvider).listMeasurements(scope);
    _cursor = page.nextCursor;
    return MeasurementListState(items: page.items, hasMore: page.hasMore);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;

    final page = await ref
        .read(evolutionRepositoryProvider)
        .listMeasurements(arg, cursor: _cursor);
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
    await ref.read(evolutionRepositoryProvider).createMeasurement(arg, draft);
    ref.invalidateSelf();
    await future;
  }

  Future<void> delete(String id) async {
    await ref.read(evolutionRepositoryProvider).deleteMeasurement(arg, id);
    ref.invalidateSelf();
    await future;
  }
}

final measurementsProvider = AsyncNotifierProvider.autoDispose.family<
    MeasurementsController, MeasurementListState, EvolutionScope>(
  MeasurementsController.new,
);
