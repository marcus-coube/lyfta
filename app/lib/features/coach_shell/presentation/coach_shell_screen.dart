import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_shell_scaffold.dart';
import '../../../shared/widgets/role_context_switcher.dart';
import '../../library/presentation/library_screen.dart';
import '../../students/presentation/students_screen.dart';

/// Shell do professor — Alunos, Biblioteca e Chat. Lateral em telas largas
/// (web/desktop), barra inferior em mobile (`LyShellScaffold`, breakpoint
/// ~840px). Alunos e Biblioteca são as telas reais do P1.6; o chat chega no
/// P3.
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
      LyShellDestination(icon: Icons.fitness_center_outlined, label: l10n.homeCoachTabLibrary),
      LyShellDestination(icon: Icons.chat_bubble_outline, label: l10n.homeCoachTabChat),
    ];

    return LyShellScaffold(
      // O título segue a aba: com telas reais (P1.6) um título fixo mentiria
      // ("Alunos" em cima da biblioteca).
      title: destinations[_index].label,
      destinations: destinations,
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      actions: [
        if (authState.hasBothRoles)
          const RoleContextSwitcher(current: ActiveContext.coach),
      ],
      body: switch (_index) {
        0 => const StudentsScreen(),
        1 => const LibraryScreen(),
        _ => Center(
            child: Text(
              l10n.homePlaceholderBody,
              style: LyType.body(c.textSecondary),
            ),
          ),
      },
    );
  }
}
