import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/format/metric_format.dart';
import '../../../shared/l10n/measurement_l10n.dart';
import '../domain/evolution_summary.dart';
import 'delta_badge.dart';

/// Cartões do resumo do aluno (P2.5): última medida, última bioimpedância e
/// contagem de fotos, com os deltas que o `assessment` calcula contra o
/// registro anterior (P2.3).
///
/// Widget "burro" como o resto de `evolution/widgets/`: recebe o resumo
/// pronto, não sabe de onde veio.
class SummaryCard extends StatelessWidget {
  const SummaryCard({required this.summary, super.key});

  final EvolutionSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    final measurement = summary.latestMeasurement;
    final bioimpedance = summary.latestBioimpedance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.evolutionSummaryLatestMeasurement,
                style: LyType.title(c.textPrimary),
              ),
              const SizedBox(height: LySpace.x2),
              if (measurement == null)
                Text(
                  l10n.evolutionMeasurementsEmpty,
                  style: LyType.body(c.textSecondary),
                )
              else ...[
                Text(
                  date.format(measurement.measuredAt),
                  style: LyType.caption(c.textSecondary),
                ),
                const SizedBox(height: LySpace.x2),
                _MetricRow(
                  label: measurementFieldLabel(l10n, 'weight_kg'),
                  value: measurement.weightKg,
                  delta: summary.deltas.weightKg,
                ),
                _MetricRow(
                  label: measurementFieldLabel(l10n, 'waist_cm'),
                  value: measurement.waistCm,
                  delta: summary.deltas.waistCm,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: LySpace.x3),
        LyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.evolutionSummaryLatestBioimpedance,
                style: LyType.title(c.textPrimary),
              ),
              const SizedBox(height: LySpace.x2),
              if (bioimpedance == null)
                Text(
                  l10n.evolutionBioimpedanceEmpty,
                  style: LyType.body(c.textSecondary),
                )
              else ...[
                Text(
                  date.format(bioimpedance.measuredAt),
                  style: LyType.caption(c.textSecondary),
                ),
                const SizedBox(height: LySpace.x2),
                _MetricRow(
                  label: bioimpedanceFieldLabel(l10n, 'body_fat_pct'),
                  value: bioimpedance.bodyFatPct,
                  delta: summary.deltas.bodyFatPct,
                ),
                _MetricRow(
                  label: bioimpedanceFieldLabel(l10n, 'muscle_mass_kg'),
                  value: bioimpedance.muscleMassKg,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: LySpace.x3),
        LyCard(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.evolutionSummaryPhotoCount,
                  style: LyType.body(c.textPrimary),
                ),
              ),
              Text(
                '${summary.photoCount}',
                style: LyType.title(c.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Uma linha "rótulo — valor — delta". Campo não medido some da leitura em
/// vez de virar traço: o resumo mostra o que foi medido, não a ficha inteira.
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value, this.delta});

  final String label;
  final double? value;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    final metric = value;
    if (metric == null) return const SizedBox.shrink();
    final c = context.ly;
    final locale = Localizations.localeOf(context).toString();

    return Padding(
      padding: const EdgeInsets.only(top: LySpace.x1),
      child: Row(
        children: [
          Expanded(child: Text(label, style: LyType.body(c.textSecondary))),
          Text(formatMetric(metric, locale), style: LyType.body(c.textPrimary)),
          const SizedBox(width: LySpace.x2),
          DeltaBadge(value: delta),
        ],
      ),
    );
  }
}
