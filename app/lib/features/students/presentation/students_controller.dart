import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/providers.dart';
import '../../builder/data/plan_repository.dart';
import '../../../shared/domain/plan.dart';
import '../data/student_repository.dart';
import '../domain/student.dart';

/// Repositório da lista de alunos sobre o cliente HTTP do `identity`.
final studentRepositoryProvider = Provider<StudentRepository>((ref) {
  return StudentRepository(ref.watch(identityApiClientProvider).dio);
});

/// Busca digitada na tela de alunos.
final studentQueryProvider = StateProvider<String>((ref) => '');

/// Um aluno com o plano que ele está fazendo agora, se houver.
class StudentRow {
  const StudentRow({required this.student, this.activePlan});

  final Student student;
  final PlanSummary? activePlan;
}

/// Lista de alunos do professor já cruzada com o plano ativo de cada um.
///
/// São dois serviços: a lista vem do `identity` (quem é aluno do tenant) e o
/// plano vem do `workout` (ADR-013 §2 — nenhum lê o banco do outro). O
/// cruzamento é aqui, no cliente, que é quem tem sessão nos dois.
class StudentsController extends AsyncNotifier<List<StudentRow>> {
  /// Tamanho da página. Deliberadamente curto: hoje o plano de cada aluno é
  /// uma chamada por linha (N+1), e uma página grande viraria uma rajada de
  /// requisições. Um endpoint de resumo em lote resolve quando doer.
  static const int pageSize = 20;

  @override
  Future<List<StudentRow>> build() async {
    final query = ref.watch(studentQueryProvider);
    final page = await ref.watch(studentRepositoryProvider).list(query: query, limit: pageSize);

    final plans = ref.read(planRepositoryProvider);
    final rows = await Future.wait(
      page.items.map((student) async {
        try {
          final summaries = await plans.byStudent(student.id);
          return StudentRow(
            student: student,
            activePlan: summaries.where((p) => p.isActive).firstOrNull ?? summaries.firstOrNull,
          );
        } catch (_) {
          // Falha ao ler o plano de um aluno não pode apagar a lista inteira:
          // a linha aparece sem plano e o professor ainda consegue trabalhar.
          return StudentRow(student: student);
        }
      }),
    );
    return rows;
  }

  /// Recarrega a lista. `invalidateSelf` e não `build()` na mão: chamar o
  /// build direto executa `ref.watch` fora do ciclo do Riverpod, e o
  /// resultado não substitui o estado que a tela observa — foi assim que a
  /// lista continuou dizendo "sem plano" depois de publicar.
  void refresh() => ref.invalidateSelf();
}

final studentsProvider = AsyncNotifierProvider<StudentsController, List<StudentRow>>(
  StudentsController.new,
);
