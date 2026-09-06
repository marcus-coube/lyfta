import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/evolution_scope.dart';
import 'evolution_screen.dart';

/// Ficha de evolução de um aluno, vista pelo professor (P2.5).
///
/// A tela é só a moldura: o conteúdo é a mesma [EvolutionScreen] da aba do
/// aluno (P2.4), com o escopo trocado — é isso que faz os widgets renderem
/// nos dois shells sem duplicação, e o que o Aceite da tarefa cobra.
class StudentEvolutionScreen extends StatelessWidget {
  const StudentEvolutionScreen({
    required this.studentId,
    this.studentName,
    super.key,
  });

  final String studentId;

  /// Vem por `extra` da lista de alunos. Nulo quando a rota é aberta direto
  /// pela URL (recarregar a página na web) — aí o título genérico serve, em
  /// vez de segurar a tela inteira só para buscar um nome.
  final String? studentName;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(studentName ?? l10n.evolutionStudentTitle)),
      body: SafeArea(
        child: EvolutionScreen(scope: EvolutionScope.student(studentId)),
      ),
    );
  }
}
