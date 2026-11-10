import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/providers.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/presentation/billing_providers.dart';
import '../data/student_overview_repository.dart';
import '../data/student_repository.dart';
import '../domain/student.dart';
import '../domain/student_overview.dart';

/// Repositório da lista de alunos sobre o cliente HTTP do `identity`.
final studentRepositoryProvider = Provider<StudentRepository>((ref) {
  return StudentRepository(ref.watch(identityApiClientProvider).dio);
});

/// Busca digitada na tela de alunos.
final studentQueryProvider = StateProvider<String>((ref) => '');

/// Filtro de status; o padrão são os ativos (P5.4).
final studentStatusFilterProvider =
    StateProvider<StudentStatusFilter>((ref) => StudentStatusFilter.active);

/// Filtro por professor — só o owner usa (o coach já recebe só os seus).
final studentCoachFilterProvider = StateProvider<String?>((ref) => null);

/// Ficha de um aluno (`GET /v1/students/{id}`). `autoDispose`: reabrir a ficha
/// sempre traz o dado do servidor.
final studentDetailProvider =
    FutureProvider.autoDispose.family<Student, String>((ref, id) {
  return ref.watch(studentRepositoryProvider).get(id);
});

/// Histórico de status do aluno.
final studentStatusHistoryProvider =
    FutureProvider.autoDispose.family<List<StatusEvent>, String>((ref, id) {
  return ref.watch(studentRepositoryProvider).statusHistory(id);
});

/// Resumo em lote do `workout` sobre o cliente HTTP dele.
final studentOverviewRepositoryProvider =
    Provider<StudentOverviewRepository>((ref) {
  return StudentOverviewRepository(ref.watch(workoutApiClientProvider).dio);
});

/// Um aluno com o plano que ele está fazendo agora e o último treino, se
/// houver (nulos também quando o `workout` não respondeu).
class StudentRow {
  const StudentRow({
    required this.student,
    this.overview,
    this.billingStatus,
  });

  final Student student;
  final StudentOverview? overview;

  /// `ok`, `delinquent` ou `none` (P7.4); nulo quando o `billing` não
  /// respondeu.
  final String? billingStatus;

  bool get isDelinquent => billingStatus == 'delinquent';

  ActivePlan? get activePlan => overview?.activePlan;
  DateTime? get lastSessionAt => overview?.lastSessionAt;
}

/// Linhas já carregadas e o que falta: o cursor da próxima página, se houver.
class StudentsState {
  const StudentsState({
    required this.rows,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<StudentRow> rows;
  final String? nextCursor;
  final bool loadingMore;

  /// A última tentativa de carregar a próxima página falhou: o rodapé mostra
  /// "tentar de novo" em vez de repetir sozinho (senão vira laço de requisição
  /// com a API fora).
  final bool loadMoreFailed;

  bool get hasMore => nextCursor != null;

  StudentsState copyWith({
    List<StudentRow>? rows,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) {
    return StudentsState(
      rows: rows ?? this.rows,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    );
  }
}

/// Lista de alunos do professor, paginada pelo cursor do servidor e já
/// cruzada com o plano ativo, o último treino e o selo de inadimplência de
/// cada um.
///
/// São dois serviços: a lista vem do `identity` (quem é aluno do tenant) e
/// plano/último treino vêm do `workout` (ADR-013 §2 — nenhum lê o banco do
/// outro), numa única chamada em lote por página. O cruzamento é aqui, no
/// cliente, que é quem tem sessão nos dois.
class StudentsController extends AsyncNotifier<StudentsState> {
  /// Tamanho da página (<= teto do resumo em lote); a lista continua sem teto
  /// porque o rodapé pede a próxima página ao rolar.
  static const int pageSize = 50;

  /// Conta os recomeços da lista (busca, filtro, refresh): uma página que
  /// voltou de uma consulta anterior é descartada em vez de misturar alunos de
  /// filtros diferentes.
  int _generation = 0;

  @override
  Future<StudentsState> build() async {
    _generation++;
    // `watch` aqui (e `read` no resto) é o que faz mudar a busca ou um filtro
    // recomeçar a lista.
    ref
      ..watch(studentQueryProvider)
      ..watch(studentStatusFilterProvider)
      ..watch(studentCoachFilterProvider)
      // Baixa, estorno ou assinatura mudam o selo "inadimplente".
      ..watch(billingVersionProvider);
    final page = await _fetch(cursor: null);
    return StudentsState(
      rows: await _withOverview(page.items),
      nextCursor: page.nextCursor,
    );
  }

  Future<StudentPage> _fetch({required String? cursor}) {
    return ref.read(studentRepositoryProvider).list(
          query: ref.read(studentQueryProvider),
          status: ref.read(studentStatusFilterProvider),
          coachId: ref.read(studentCoachFilterProvider),
          cursor: cursor,
          limit: pageSize,
        );
  }

  Future<List<StudentRow>> _withOverview(List<Student> students) async {
    Map<String, StudentOverview> overview;
    try {
      overview = await ref
          .read(studentOverviewRepositoryProvider)
          .overview([for (final s in students) s.id]);
    } catch (_) {
      // O `workout` fora do ar não pode apagar a lista: as linhas aparecem
      // sem plano/último treino e o professor ainda consegue trabalhar.
      overview = const {};
    }
    Map<String, String> billing;
    try {
      billing = await ref
          .read(billingRepositoryProvider)
          .studentStatuses([for (final s in students) s.id]);
    } catch (_) {
      // Idem para o `billing`: sem selo, a lista continua.
      billing = const {};
    }
    return [
      for (final s in students)
        StudentRow(
          student: s,
          overview: overview[s.id],
          billingStatus: billing[s.id],
        ),
    ];
  }

  /// Carrega a página seguinte e a acrescenta. Ignora chamadas enquanto outra
  /// está em andamento e quando não há mais páginas.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;

    final generation = _generation;
    state =
        AsyncData(current.copyWith(loadingMore: true, loadMoreFailed: false));
    try {
      final page = await _fetch(cursor: current.nextCursor);
      final rows = await _withOverview(page.items);
      if (generation != _generation) return;
      state = AsyncData(
        StudentsState(
          rows: [...current.rows, ...rows],
          nextCursor: page.nextCursor,
        ),
      );
    } catch (_) {
      if (generation != _generation) return;
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreFailed: true),
      );
    }
  }

  /// Recarrega a lista do começo. `invalidateSelf` e não `build()` na mão:
  /// chamar o build direto executa `ref.watch` fora do ciclo do Riverpod, e o
  /// resultado não substitui o estado que a tela observa — foi assim que a
  /// lista continuou dizendo "sem plano" depois de publicar.
  void refresh() => ref.invalidateSelf();
}

final studentsProvider =
    AsyncNotifierProvider<StudentsController, StudentsState>(
  StudentsController.new,
);
