import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/plan.dart';
import '../data/variation_repository.dart';
import '../domain/variation_status.dart';

/// Busca e filtro de arquivadas da tela Variações.
typedef VariationFilter = ({String query, bool showArchived});

final variationFilterProvider = StateProvider.autoDispose<VariationFilter>(
  (ref) => (query: '', showArchived: false),
);

/// Lista da tela: ativas e, se pedido, as arquivadas ao final.
final variationsListProvider =
    FutureProvider.autoDispose<List<SetVariation>>((ref) async {
  final filter = ref.watch(variationFilterProvider);
  final items = await ref.watch(variationRepositoryProvider).list(
        query: filter.query,
        status: filter.showArchived
            ? VariationStatus.all
            : VariationStatus.active,
      );
  // Ativas primeiro; dentro de cada grupo a ordem de nome do servidor.
  return [
    ...items.where((v) => !v.archived),
    ...items.where((v) => v.archived),
  ];
});

/// Variações ativas para o seletor do builder, filtradas pela busca.
final variationPickerProvider = FutureProvider.autoDispose
    .family<List<SetVariation>, String>((ref, query) {
  return ref.watch(variationRepositoryProvider).list(query: query);
});
