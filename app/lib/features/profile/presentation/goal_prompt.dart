import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../evolution/domain/evolution_scope.dart';
import '../data/goal_prompt_storage.dart';
import 'profile_controller.dart';

/// Sugere uma única vez, depois do primeiro login, preencher o objetivo
/// (P5.5). Só aparece se a anamnese está sem objetivo e o aparelho ainda não
/// mostrou o convite a este usuário. Falha de rede não marca como mostrado:
/// tenta de novo na próxima abertura do app.
Future<void> maybeShowGoalPrompt(BuildContext context, WidgetRef ref) async {
  final userId = ref.read(authControllerProvider).userId;
  if (userId == null) return;
  final storage = ref.read(goalPromptStorageProvider);
  try {
    if (await storage.wasShown(userId)) return;
    final profile = await ref
        .read(studentProfileProvider(const EvolutionScope.me()).future);
    // Quem já preencheu (outro aparelho, ou o professor) não precisa do convite.
    if (profile.goal != null) {
      await storage.markShown(userId);
      return;
    }
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  await storage.markShown(userId);
  if (!context.mounted) return;

  final l10n = AppLocalizations.of(context);
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.goalPromptTitle),
      content: Text(l10n.goalPromptBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.goalPromptLater),
        ),
        TextButton(
          key: const Key('goal_prompt_accept'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.goalPromptNow),
        ),
      ],
    ),
  );
  if (accepted == true && context.mounted) {
    await context.push('/goal');
  }
}
