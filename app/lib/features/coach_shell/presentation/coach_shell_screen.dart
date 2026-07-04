import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/role_context_switcher.dart';

/// Shell do professor — navegação por destinos placeholder (Alunos, Treinos,
/// Chat). Telas reais chegam nas fases seguintes do plano.
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
      (icon: Icons.groups_outlined, label: l10n.homeCoachTabStudents),
      (icon: Icons.fitness_center_outlined, label: l10n.homeCoachTabWorkouts),
      (icon: Icons.chat_bubble_outline, label: l10n.homeCoachTabChat),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeCoachTitle),
        actions: [
          if (authState.hasBothRoles)
            const RoleContextSwitcher(current: ActiveContext.coach),
        ],
      ),
      body: Center(
        child: Text(l10n.homePlaceholderBody, style: LyType.body(c.textSecondary)),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in destinations)
            NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}
