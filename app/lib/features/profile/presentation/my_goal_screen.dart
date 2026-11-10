import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../evolution/domain/evolution_scope.dart';
import 'health_section.dart';

/// "Meu objetivo" (P5.5): o aluno edita objetivo, experiência, meta semanal e
/// observações médicas. Acessível pela Conta e sugerida uma vez no primeiro
/// acesso (`GoalPrompt`).
class MyGoalScreen extends StatelessWidget {
  const MyGoalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myGoalTitle)),
      body: ListView(
        padding: const EdgeInsets.all(LySpace.x4),
        children: [
          Text(
            l10n.myGoalIntro,
            style: LyType.body(context.ly.textSecondary),
          ),
          const SizedBox(height: LySpace.x4),
          const HealthSection(scope: EvolutionScope.me()),
        ],
      ),
    );
  }
}
