import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_shell_scaffold.dart';
import '../../../shared/widgets/role_context_switcher.dart';

/// Shell do professor — navegação por destinos placeholder (Alunos, Treinos,
/// Chat). Lateral em telas largas (web/desktop), barra inferior em mobile
/// (`LyShellScaffold`, breakpoint ~840px). Telas reais chegam nas fases
/// seguintes do plano.
class CoachShellScreen extends ConsumerStatefulWidget {
  const CoachShellScreen({super.key});

  @override
  ConsumerState<CoachShellScreen> createState() => _CoachShellScreenState();
}

class _CoachShellScreenState extends ConsumerState<CoachShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authControllerProvider);

    final destinations = [
      LyShellDestination(icon: Icons.groups_outlined, label: l10n.homeCoachTabStudents),
      LyShellDestination(icon: Icons.fitness_center_outlined, label: l10n.homeCoachTabWorkouts),
      LyShellDestination(icon: Icons.chat_bubble_outline, label: l10n.homeCoachTabChat),
    ];

    return LyShellScaffold(
      title: l10n.homeCoachTitle,
      destinations: destinations,
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      actions: [
        if (authState.hasBothRoles)
          const RoleContextSwitcher(current: ActiveContext.coach),
      ],
      body: Center(
        child: Text(l10n.homePlaceholderBody, style: LyType.body(c.textSecondary)),
      ),
    );
  }
}
