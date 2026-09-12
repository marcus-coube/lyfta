import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/l10n/gen/app_localizations.dart';
import '../../domain/agenda_day.dart';

/// Detalhe de um dia tocado na agenda (P4.1 Aceite: "resumo volume/duração
/// ao tocar"). Sessão sincronizada mostra o resumo; previsão e descanso só
/// explicam o que a célula significa.
Future<void> showAgendaDayDetails(BuildContext context, AgendaDay day) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AgendaDayDetails(day: day),
  );
}

class _AgendaDayDetails extends StatelessWidget {
  const _AgendaDayDetails({required this.day});

  final AgendaDay day;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final dateLabel = DateFormat.yMMMEd(locale).format(day.date);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(LySpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateLabel, style: LyType.caption(c.textSecondary)),
            const SizedBox(height: LySpace.x2),
            Text(_title(l10n), style: LyType.h2(c.textPrimary)),
            const SizedBox(height: LySpace.x6),
            switch (day.state) {
              AgendaDayState.done => _SessionMetrics(day: day),
              AgendaDayState.predicted => Text(
                  l10n.agendaPredictedHint,
                  style: LyType.body(c.textSecondary),
                ),
              AgendaDayState.rest => Text(
                  l10n.agendaRestHint,
                  style: LyType.body(c.textSecondary),
                ),
            },
            const SizedBox(height: LySpace.x8),
            LyButton(
              label: l10n.sessionSummaryClose,
              variant: LyButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  String _title(AppLocalizations l10n) => switch (day.state) {
        AgendaDayState.done => l10n.agendaSessionTitle(day.dayLabel ?? ''),
        AgendaDayState.predicted =>
          l10n.agendaPredictedTitle(day.dayLabel ?? ''),
        AgendaDayState.rest => l10n.agendaRestTitle,
      };
}

class _SessionMetrics extends StatelessWidget {
  const _SessionMetrics({required this.day});

  final AgendaDay day;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final minutes = day.totalDuration.inMinutes;

    return Row(
      children: [
        _Metric(
          label: l10n.sessionSummarySets,
          value: day.totalSets.toString(),
        ),
        _Metric(
          label: l10n.sessionSummaryVolume,
          value: _formatVolume(day.totalVolumeKg),
        ),
        if (minutes > 0)
          _Metric(
            label: l10n.sessionSummaryDuration,
            value: l10n.sessionDurationMinutes(minutes),
          ),
      ],
    );
  }

  // Mesma regra de `formatLoad`/`formatMetric` (sem `.0` decorativo),
  // duplicada aqui de propósito: feature não importa feature (guideline
  // `flutter.md`).
  String _formatVolume(double value) {
    final rounded = (value * 100).round() / 100;
    if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
    return rounded.toString();
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
          Text(value, style: LyType.numeric(c.textPrimary, size: 24)),
          const SizedBox(height: LySpace.x1),
          Text(label, style: LyType.caption(c.textSecondary)),
        ],
      ),
    );
  }
}
