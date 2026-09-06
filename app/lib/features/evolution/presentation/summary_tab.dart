import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/evolution_scope.dart';
import '../widgets/summary_card.dart';
import 'summary_controller.dart';

/// Aba Resumo da ficha do aluno (P2.5) — só existe no escopo do coach.
class SummaryTab extends ConsumerWidget {
  const SummaryTab({required this.scope, super.key});

  final EvolutionScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final summary = ref.watch(evolutionSummaryProvider(scope));

    return summary.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              describeApiError(context, error),
              style: LyType.body(c.textSecondary),
            ),
            const SizedBox(height: LySpace.x3),
            LyButton(
              label: l10n.commonRetry,
              variant: LyButtonVariant.secondary,
              expanded: false,
              onPressed: () => ref.invalidate(evolutionSummaryProvider(scope)),
            ),
          ],
        ),
      ),
      data: (data) => ListView(
        padding: const EdgeInsets.fromLTRB(
          LySpace.x4,
          LySpace.x4,
          LySpace.x4,
          LySpace.x16,
        ),
        children: [SummaryCard(summary: data)],
      ),
    );
  }
}
