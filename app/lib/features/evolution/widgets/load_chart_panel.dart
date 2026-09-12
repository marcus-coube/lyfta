import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/format/metric_format.dart';
import '../domain/exercise_history.dart';
import '../presentation/load_controller.dart';

/// Gráfico de progressão de um exercício (P2.4 §1): toggle carga máxima ×
/// volume e seletor de janela (1m/3m/6m/tudo). Widget "burro" — recebe os
/// pontos já filtrados pelo controller, para o P2.5 reusar com o controller
/// do coach.
class LoadChartPanel extends StatelessWidget {
  const LoadChartPanel({
    required this.points,
    required this.metric,
    required this.onMetricChanged,
    required this.range,
    required this.onRangeChanged,
    super.key,
  });

  final List<ExerciseHistoryPoint> points;
  final LoadMetric metric;
  final ValueChanged<LoadMetric> onMetricChanged;
  final LoadRange range;
  final ValueChanged<LoadRange> onRangeChanged;

  double? _valueOf(ExerciseHistoryPoint p) =>
      metric == LoadMetric.maxLoad ? p.maxLoadKg : p.totalVolumeKg;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    final series = <MapEntry<DateTime, double>>[
      for (final p in points)
        if (_valueOf(p) != null) MapEntry(p.performedAt, _valueOf(p)!),
    ];

    return LyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<LoadMetric>(
            segments: [
              ButtonSegment(
                value: LoadMetric.maxLoad,
                label: Text(l10n.evolutionMetricMaxLoad),
              ),
              ButtonSegment(
                value: LoadMetric.volume,
                label: Text(l10n.evolutionMetricVolume),
              ),
            ],
            selected: {metric},
            onSelectionChanged: (selection) => onMetricChanged(selection.first),
          ),
          const SizedBox(height: LySpace.x3),
          Wrap(
            spacing: LySpace.x2,
            children: [
              for (final option in LoadRange.values)
                ChoiceChip(
                  label: Text(_rangeLabel(l10n, option)),
                  selected: range == option,
                  onSelected: (_) => onRangeChanged(option),
                ),
            ],
          ),
          const SizedBox(height: LySpace.x4),
          SizedBox(
            height: 220,
            child: series.isEmpty
                ? Center(
                    child: Text(
                      l10n.evolutionNoDataForRange,
                      style: LyType.body(c.textSecondary),
                    ),
                  )
                : _Chart(
                    series: series,
                    lineColor: c.accent,
                    gridColor: c.border,
                    labelColor: c.textSecondary,
                  ),
          ),
        ],
      ),
    );
  }

  String _rangeLabel(AppLocalizations l10n, LoadRange range) => switch (range) {
        LoadRange.oneMonth => l10n.evolutionRangeOneMonth,
        LoadRange.threeMonths => l10n.evolutionRangeThreeMonths,
        LoadRange.sixMonths => l10n.evolutionRangeSixMonths,
        LoadRange.all => l10n.evolutionRangeAll,
      };
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.series,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<MapEntry<DateTime, double>> series;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < series.length; i++)
        FlSpot(i.toDouble(), series[i].value),
    ];
    final locale = Localizations.localeOf(context).toString();
    final dateFormat = DateFormat.MMMd(locale);
    // No máximo ~5 rótulos no eixo X: com muitos pontos, um por sessão vira
    // ilegível.
    final labelStep = (series.length / 5).ceil().clamp(1, series.length);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: gridColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                formatMetric(value, locale),
                style: LyType.caption(labelColor),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              // Sem `interval`, o fl_chart chama este builder em frações do
              // eixo (0.0, 0.2, 0.4…) e `round()` mapeia várias delas para o
              // mesmo ponto — a mesma data sai repetida lado a lado. O passo
              // é o índice do ponto, então o intervalo é ele mesmo.
              interval: labelStep.toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 ||
                    index >= series.length ||
                    index % labelStep != 0 ||
                    (value - index).abs() > 0.01) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: LySpace.x1),
                  child: Text(
                    dateFormat.format(series[index].key),
                    style: LyType.caption(labelColor),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => [
              for (final spot in touchedSpots)
                LineTooltipItem(
                  '${formatMetric(spot.y, locale)}\n${dateFormat.format(series[spot.x.round()].key)}',
                  LyType.caption(labelColor)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: lineColor,
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}
