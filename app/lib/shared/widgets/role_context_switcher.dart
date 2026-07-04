import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/l10n/gen/app_localizations.dart';

/// Seletor de contexto (professor ↔ aluno) exibido no app bar de ambos os
/// shells quando o usuário acumula os dois papéis (`AuthState.hasBothRoles`).
class RoleContextSwitcher extends ConsumerWidget {
  const RoleContextSwitcher({required this.current, super.key});

  final ActiveContext current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return PopupMenuButton<ActiveContext>(
      icon: const Icon(Icons.swap_horiz),
      initialValue: current,
      onSelected: (value) =>
          ref.read(authControllerProvider.notifier).switchContext(value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: ActiveContext.coach,
          child: Text(l10n.roleSwitcherCoach),
        ),
        PopupMenuItem(
          value: ActiveContext.student,
          child: Text(l10n.roleSwitcherStudent),
        ),
      ],
    );
  }
}
