import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/template_repository.dart';
import '../domain/template.dart';

/// Busca digitada na aba Modelos.
final templateQueryProvider = StateProvider<String>((ref) => '');

/// Mostra os arquivados em vez dos ativos.
final templateArchivedFilterProvider = StateProvider<bool>((ref) => false);

class TemplatesState {
  const TemplatesState({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<TemplateSummary> items;
  final String? nextCursor;
  final bool loadingMore;
  final bool loadMoreFailed;

  bool get hasMore => nextCursor != null;
}

/// Biblioteca de modelos do tenant, paginada pelo cursor do servidor. Busca e
/// filtro recomeçam a lista (mesma ideia da lista de alunos).
class TemplatesController extends AsyncNotifier<TemplatesState> {
  static const int pageSize = 30;

  int _generation = 0;

  @override
  Future<TemplatesState> build() async {
    _generation++;
    final query = ref.watch(templateQueryProvider);
    final archived = ref.watch(templateArchivedFilterProvider);
    final page = await ref.read(templateRepositoryProvider).list(
          query: query,
          status: archived ? 'archived' : '',
          limit: pageSize,
        );
    return TemplatesState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(
      TemplatesState(
        items: current.items,
        nextCursor: current.nextCursor,
        loadingMore: true,
      ),
    );
    try {
      final page = await ref.read(templateRepositoryProvider).list(
            query: ref.read(templateQueryProvider),
            status: ref.read(templateArchivedFilterProvider) ? 'archived' : '',
            cursor: current.nextCursor,
            limit: pageSize,
          );
      if (generation != _generation) return;
      state = AsyncData(
        TemplatesState(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } catch (_) {
      if (generation != _generation) return;
      state = AsyncData(
        TemplatesState(
          items: current.items,
          nextCursor: current.nextCursor,
          loadMoreFailed: true,
        ),
      );
    }
  }

  void refresh() => ref.invalidateSelf();
}

final templatesProvider =
    AsyncNotifierProvider<TemplatesController, TemplatesState>(
  TemplatesController.new,
);
