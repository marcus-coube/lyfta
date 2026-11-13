import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/l10n/gen/app_localizations.dart';
import '../../domain/session_metrics.dart';
import '../prescription_format.dart';
import '../session_controller.dart';

/// Resumo do fim do treino: séries feitas, volume e duração (P1.7 §3).
///
/// O resumo sai do que está **no device**, não do servidor: o treino pode ter
/// acabado em modo avião, e o aluno merece ver o que fez na hora.
Future<void> showSessionSummary(BuildContext context, SessionState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _SessionSummary(state: state),
  );
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final metrics = state.metrics();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(LySpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sessionSummaryTitle, style: LyType.h2(c.textPrimary)),
            const SizedBox(height: LySpace.x1),
            Text(
              l10n.sessionTitle(state.session.dayLabel),
              style: LyType.bodySm(c.textSecondary),
            ),
            const SizedBox(height: LySpace.x6),
            SessionMetricsGrid(metrics: metrics),
            const SizedBox(height: LySpace.x8),
            LyButton(
              label: l10n.sessionSummaryClose,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// As quatro métricas do treino em grade 2×2 — o resumo final e o modal de
/// treino concluído mostram a mesma coisa.
class SessionMetricsGrid extends StatelessWidget {
  const SessionMetricsGrid({
    super.key,
    required this.metrics,
    this.durationKnown = true,
  });

  final SessionMetrics metrics;

  /// Falso quando a duração não é confiável (check-in visto pelo professor,
  /// P11.2): mostra "—" em vez de `0:00:00`.
  final bool durationKnown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Row(
          children: [
            _Metric(
              label: l10n.sessionSummarySets,
              value: metrics.sets.toString(),
            ),
            _Metric(
              label: l10n.sessionSummaryReps,
              value: metrics.reps.toString(),
            ),
          ],
        ),
        const SizedBox(height: LySpace.x4),
        Row(
          children: [
            _Metric(
              label: l10n.sessionSummaryVolume,
              value: formatLoad(metrics.volumeKg, l10n.localeName),
            ),
            _Metric(
              label: l10n.sessionSummaryDuration,
              value: durationKnown ? formatClock(metrics.duration) : '—',
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: LyType.numeric(c.textPrimary, size: 28)),
          const SizedBox(height: LySpace.x1),
          Text(label, style: LyType.caption(c.textSecondary)),
        ],
      ),
    );
  }
}
