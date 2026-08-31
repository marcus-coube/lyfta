import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/exercise_repository.dart';
import '../../../shared/domain/exercise.dart';

/// Filtros ativos da tela da biblioteca. Fica fora do controller para que
/// mudar filtro seja uma escrita simples e o carregamento reaja a ela.
final libraryFilterProvider =
    StateProvider<ExerciseFilter>((ref) => const ExerciseFilter());

/// Estado da lista: a página acumulada mais a marca de que há mais itens.
class LibraryState {
  const LibraryState({
    this.items = const [],
    this.hasMore = false,
    this.loadingMore = false,
  });

  final List<Exercise> items;
  final bool hasMore;
  final bool loadingMore;

  LibraryState copyWith({
    List<Exercise>? items,
    bool? hasMore,
    bool? loadingMore,
  }) {
    return LibraryState(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
    );
  }
}

/// Lista paginada da biblioteca, recarregada sempre que o filtro muda.
///
/// O cursor é opaco (keyset no servidor): guardamos o último recebido e
/// devolvemos como veio.
class LibraryController extends AsyncNotifier<LibraryState> {
  String? _cursor;

  @override
  Future<LibraryState> build() async {
    // `watch` no filtro: digitar na busca ou trocar de músculo reconstrói o
    // controller e refaz a primeira página, sem `listen` manual.
    final filter = ref.watch(libraryFilterProvider);
    final page = await ref
        .watch(exerciseRepositoryProvider)
        .list(filter: filter);
    _cursor = page.nextCursor;
    return LibraryState(items: page.items, hasMore: page.hasMore);
  }

  /// Carrega a próxima página e acumula na lista já exibida.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(exerciseRepositoryProvider).list(
            filter: ref.read(libraryFilterProvider),
            cursor: _cursor,
          );
      _cursor = page.nextCursor;
      state = AsyncData(
        LibraryState(
          items: [...current.items, ...page.items],
          hasMore: page.hasMore,
        ),
      );
    } catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }

  /// Recarrega a primeira página — usado depois de criar/editar exercício.
  /// `invalidateSelf` e não `build()` na mão: chamar o build direto executa
  /// `ref.watch` fora do ciclo do Riverpod e o resultado não chega à tela.
  void refresh() => ref.invalidateSelf();
}

final libraryProvider =
    AsyncNotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);
