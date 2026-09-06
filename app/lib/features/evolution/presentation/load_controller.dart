import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/evolution_repository.dart';
import '../domain/evolution_scope.dart';
import '../domain/exercise_history.dart';

/// O que o gráfico de carga desenha: carga máxima da sessão ou volume total
/// (Σ reps×carga) — o toggle do P2.4.
enum LoadMetric { maxLoad, volume }

/// Janela do gráfico. O corte é resolvido no cliente porque o histórico do
/// `workout` não tem `?since=` (nota de execução do P2.1) — a tela pagina
/// até passar da data.
enum LoadRange {
  oneMonth,
  threeMonths,
  sixMonths,
  all;

  DateTime? since(DateTime now) {
    return switch (this) {
      LoadRange.oneMonth => DateTime(now.year, now.month - 1, now.day),
      LoadRange.threeMonths => DateTime(now.year, now.month - 3, now.day),
      LoadRange.sixMonths => DateTime(now.year, now.month - 6, now.day),
      LoadRange.all => null,
    };
  }
}

/// O que a aba Carga tem selecionado: qual exercício, qual métrica, qual
/// janela. Guardado fora do controller (como o filtro da biblioteca, P1.6)
/// para que trocar seleção seja uma escrita simples.
class LoadSelection {
  const LoadSelection({
    this.exerciseId,
    this.metric = LoadMetric.maxLoad,
    this.range = LoadRange.threeMonths,
  });

  final String? exerciseId;
  final LoadMetric metric;
  final LoadRange range;

  LoadSelection copyWith({
    String? exerciseId,
    LoadMetric? metric,
    LoadRange? range,
  }) {
    return LoadSelection(
      exerciseId: exerciseId ?? this.exerciseId,
      metric: metric ?? this.metric,
      range: range ?? this.range,
    );
  }
}

/// A seleção é por escopo: a aba Carga do aluno e a ficha de cada aluno no
/// shell do coach guardam a sua — trocar de aluno não herda um exercício que
/// o outro nunca treinou.
final loadSelectionProvider = StateProvider.autoDispose
    .family<LoadSelection, EvolutionScope>((ref, scope) => const LoadSelection());

/// Exercícios já treinados, para o seletor da aba Carga.
final loggedExercisesProvider = FutureProvider.autoDispose
    .family<List<LoggedExercise>, EvolutionScope>((ref, scope) {
  return ref.watch(evolutionRepositoryProvider).loggedExercises(scope);
});

/// Parâmetros de uma busca de histórico — `family` em vez de ler
/// [loadSelectionProvider] direto: a tela pode precisar mostrar o primeiro
/// exercício da lista antes de qualquer escolha do aluno (nenhum item
/// selecionado ainda), e derivar esse "efetivo" na tela sem escrever de
/// volta no provider evita depender de timing de `ref.listen`/callback de
/// frame para sincronizar os dois.
typedef ExerciseHistoryQuery = ({
  EvolutionScope scope,
  String exerciseId,
  DateTime? since,
});

/// Série de um exercício, em ordem crescente de data (o servidor devolve
/// decrescente — quem inverte para o eixo do tempo é o cliente, mesma nota
/// de execução do P2.1).
final exerciseHistoryProvider = FutureProvider.autoDispose
    .family<List<ExerciseHistoryPoint>, ExerciseHistoryQuery>(
        (ref, query) async {
  final points = await ref
      .watch(evolutionRepositoryProvider)
      .exerciseHistory(query.scope, query.exerciseId, since: query.since);
  return points.reversed.toList();
});
