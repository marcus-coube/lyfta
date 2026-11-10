import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/account_button.dart';
import '../../../shared/widgets/ly_shell_scaffold.dart';
import '../../../shared/widgets/role_context_switcher.dart';
import '../../billing/presentation/billing_providers.dart';
import '../../billing/presentation/finance_screen.dart';
import '../../chat/presentation/chat_home_screen.dart';
import '../../chat/presentation/conversations_controller.dart';
import '../../library/presentation/library_screen.dart';
import '../../students/presentation/students_screen.dart';
import '../../templates/presentation/templates_screen.dart';

/// Shell do professor — Alunos, Biblioteca, Modelos (P6.3), Financeiro (P7.4, só
/// owner e coach `own_students`) e Chat. Lateral em telas largas
/// (web/desktop), barra inferior em mobile (`LyShellScaffold`, breakpoint
/// ~840px). Alunos e Biblioteca são as telas reais do P1.6; o Chat é a do
/// P3.5 (lista de conversas com o badge de não lidas na própria aba).
class CoachShellScreen extends ConsumerStatefulWidget {
  const CoachShellScreen({super.key});

  @override
  ConsumerState<CoachShellScreen> createState() => _CoachShellScreenState();
}

enum _CoachTab { students, library, templates, billing, chat }

class _CoachShellScreenState extends ConsumerState<CoachShellScreen> {
  // A aba é guardada pela identidade, não pelo índice: o Financeiro aparece
  // quando a configuração da organização chega e empurraria as de baixo.
  _CoachTab _tab = _CoachTab.students;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authControllerProvider);
    final unread = ref.watch(unreadTotalProvider);

    final showBilling = ref.watch(billingAccessProvider).canOperate;
    final tabs = [
      for (final t in _CoachTab.values)
        if (t != _CoachTab.billing || showBilling) t,
    ];
    final tab = tabs.contains(_tab) ? _tab : _CoachTab.students;

    LyShellDestination destination(_CoachTab t) => switch (t) {
          _CoachTab.students => LyShellDestination(
              icon: Icons.groups_outlined,
              label: l10n.homeCoachTabStudents,
            ),
          _CoachTab.library => LyShellDestination(
              icon: Icons.fitness_center_outlined,
              label: l10n.homeCoachTabLibrary,
            ),
          _CoachTab.templates => LyShellDestination(
              icon: Icons.dashboard_customize_outlined,
              label: l10n.homeCoachTabTemplates,
            ),
          _CoachTab.billing => LyShellDestination(
              icon: Icons.payments_outlined,
              label: l10n.homeCoachTabBilling,
            ),
          _CoachTab.chat => LyShellDestination(
              icon: Icons.chat_bubble_outline,
              label: l10n.homeCoachTabChat,
              badgeCount: unread,
            ),
        };
    final destinations = [for (final t in tabs) destination(t)];

    return LyShellScaffold(
      // O título segue a aba: com telas reais (P1.6) um título fixo mentiria
      // ("Alunos" em cima da biblioteca).
      title: destinations[tabs.indexOf(tab)].label,
      destinations: destinations,
      selectedIndex: tabs.indexOf(tab),
      onDestinationSelected: (i) => setState(() => _tab = tabs[i]),
      actions: [
        const AccountButton(),
        if (authState.hasBothRoles)
          const RoleContextSwitcher(current: ActiveContext.coach),
      ],
      body: switch (tab) {
        _CoachTab.students => const StudentsScreen(),
        _CoachTab.library => const LibraryScreen(),
        _CoachTab.templates => const TemplatesScreen(),
        _CoachTab.billing => const FinanceScreen(),
        _CoachTab.chat => const ChatHomeScreen(isCoach: true),
      },
    );
  }
}
