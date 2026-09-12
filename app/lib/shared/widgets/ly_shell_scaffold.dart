import 'package:flutter/material.dart';

import '../../core/design_system/design_system.dart';

/// Destino de navegação de um shell (professor/aluno).
class LyShellDestination {
  const LyShellDestination({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;

  /// Não lidas a mostrar sobre o ícone (P3.5 §1 — a aba Chat). `0` não
  /// desenha nada.
  final int badgeCount;
}

/// Breakpoint acima do qual o shell usa navegação lateral (web/desktop) em
/// vez de barra inferior (mobile) — `docs/guidelines/flutter.md` usa 600 e
/// 1024 para tablet/desktop; o plano P0.6 pede especificamente ~840 para a
/// troca de navegação dos shells.
const double lyShellRailBreakpoint = 840;

/// Scaffold responsivo comum aos shells do professor e do aluno: navegação
/// lateral (`NavigationRail`) em telas largas (web/desktop >= 840px) e barra
/// inferior (`NavigationBar`) em telas estreitas (mobile).
class LyShellScaffold extends StatelessWidget {
  const LyShellScaffold({
    required this.title,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.actions,
    super.key,
  });

  final String title;
  final List<LyShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final List<Widget>? actions;

  /// Ícone do destino, com o `Badge` do Material 3 por cima quando há não
  /// lidas (P3.5 §1) — nenhuma dependência nova, o widget já vem com o
  /// Flutter.
  Widget _badged(LyShellDestination d) {
    if (d.badgeCount <= 0) return Icon(d.icon);
    return Badge(
      label: Text(d.badgeCount > 99 ? '99+' : d.badgeCount.toString()),
      child: Icon(d.icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= lyShellRailBreakpoint;

        if (!isWide) {
          return Scaffold(
            appBar: AppBar(title: Text(title), actions: actions),
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: [
                for (final d in destinations)
                  NavigationDestination(
                    icon: _badged(d),
                    label: d.label,
                  ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(title), actions: actions),
          body: Row(
            children: [
              NavigationRail(
                backgroundColor: c.surface,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                      icon: _badged(d),
                      label: Text(d.label),
                    ),
                ],
              ),
              VerticalDivider(width: 1, color: c.border),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}
