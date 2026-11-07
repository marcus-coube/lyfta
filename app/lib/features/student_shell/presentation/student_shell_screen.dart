import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/account_button.dart';
import '../../../shared/widgets/ly_shell_scaffold.dart';
import '../../../shared/widgets/role_context_switcher.dart';
import '../../agenda/presentation/agenda_screen.dart';
import '../../chat/presentation/chat_home_screen.dart';
import '../../chat/presentation/conversations_controller.dart';
import '../../evolution/presentation/evolution_screen.dart';
import '../../workout/presentation/today_screen.dart';

/// Shell do aluno — Hoje, Evolução, Chat e Agenda. Lateral em telas largas
/// (web/desktop), barra inferior em mobile (`LyShellScaffold`, breakpoint
/// ~840px). **Hoje** é a tela real do P1.7, **Evolução** é a do P2.4, **Chat**
/// é a do P3.5 (conversa direta com o professor), **Agenda** é a do P4.1.
class StudentShellScreen extends ConsumerStatefulWidget {
  const StudentShellScreen({super.key});

  @override
  ConsumerState<StudentShellScreen> createState() => _StudentShellScreenState();
}

class _StudentShellScreenState extends ConsumerState<StudentShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authControllerProvider);
    final unread = ref.watch(unreadTotalProvider);

    final destinations = [
      LyShellDestination(
        icon: Icons.today_outlined,
        label: l10n.homeStudentTabToday,
      ),
      LyShellDestination(
        icon: Icons.show_chart_outlined,
        label: l10n.homeStudentTabEvolution,
      ),
      LyShellDestination(
        icon: Icons.chat_bubble_outline,
        label: l10n.homeStudentTabChat,
        badgeCount: unread,
      ),
      LyShellDestination(
        icon: Icons.calendar_month_outlined,
        label: l10n.homeStudentTabAgenda,
      ),
    ];

    return LyShellScaffold(
      // O título segue a aba, como no shell do professor: "Lyfta" em cima da
      // tela Hoje não diz nada ao aluno.
      title: destinations[_index].label,
      destinations: destinations,
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      actions: [
        const AccountButton(),
        if (authState.hasBothRoles)
          const RoleContextSwitcher(current: ActiveContext.student),
      ],
      body: switch (_index) {
        0 => const TodayScreen(),
        1 => const EvolutionScreen(),
        2 => const ChatHomeScreen(isCoach: false),
        _ => const AgendaScreen(),
      },
    );
  }
}
