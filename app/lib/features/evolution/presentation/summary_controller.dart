import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/evolution_repository.dart';
import '../domain/evolution_scope.dart';
import '../domain/evolution_summary.dart';

/// Resumo do aluno na ficha do coach (P2.5): última medida, última
/// bioimpedância, contagem de fotos e deltas (P2.3).
///
/// Só existe no escopo de coach — o `assessment` não expõe `/me/summary`,
/// porque a tela do aluno já tem as três listas inteiras.
final evolutionSummaryProvider = FutureProvider.autoDispose
    .family<EvolutionSummary, EvolutionScope>((ref, scope) {
  return ref.watch(evolutionRepositoryProvider).summary(scope);
});
