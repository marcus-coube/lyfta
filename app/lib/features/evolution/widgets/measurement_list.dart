import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/format/metric_format.dart';
import '../../../shared/l10n/measurement_l10n.dart';
import '../domain/measurement.dart';
import 'delta_badge.dart';

/// Histórico de medidas corporais — mais recente primeiro (a ordem que o
/// `assessment` já devolve), com o delta contra o registro seguinte da
/// lista (o anterior no tempo) em cada campo preenchido nos dois lados.
///
/// Widget "burro": só recebe os itens já carregados — quem busca/pagina é o
/// controller de quem o usa (P2.4 hoje, P2.5 depois, mesmo item da lista).
class MeasurementList extends StatelessWidget {
  const MeasurementList({
    required this.items,
    this.onDelete,
    super.key,
  });

  final List<BodyMeasurement> items;
  final ValueChanged<BodyMeasurement>? onDelete;

  static const _fieldGetters = <String, double? Function(BodyMeasurement)>{
    'weight_kg': _weight,
    'height_cm': _height,
    'neck_cm': _neck,
    'shoulder_cm': _shoulder,
    'chest_cm': _chest,
    'waist_cm': _waist,
    'abdomen_cm': _abdomen,
    'hip_cm': _hip,
    'arm_l_cm': _armL,
    'arm_r_cm': _armR,
    'thigh_l_cm': _thighL,
    'thigh_r_cm': _thighR,
    'calf_l_cm': _calfL,
    'calf_r_cm': _calfR,
  };

  static double? _weight(BodyMeasurement m) => m.weightKg;
  static double? _height(BodyMeasurement m) => m.heightCm;
  static double? _neck(BodyMeasurement m) => m.neckCm;
  static double? _shoulder(BodyMeasurement m) => m.shoulderCm;
  static double? _chest(BodyMeasurement m) => m.chestCm;
  static double? _waist(BodyMeasurement m) => m.waistCm;
  static double? _abdomen(BodyMeasurement m) => m.abdomenCm;
  static double? _hip(BodyMeasurement m) => m.hipCm;
  static double? _armL(BodyMeasurement m) => m.armLCm;
  static double? _armR(BodyMeasurement m) => m.armRCm;
  static double? _thighL(BodyMeasurement m) => m.thighLCm;
  static double? _thighR(BodyMeasurement m) => m.thighRCm;
  static double? _calfL(BodyMeasurement m) => m.calfLCm;
  static double? _calfR(BodyMeasurement m) => m.calfRCm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;

    if (items.isEmpty) {
      return Text(
        l10n.evolutionMeasurementsEmpty,
        style: LyType.body(c.textSecondary),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: LySpace.x3),
            child: LyCard(
              child: _MeasurementRow(
                item: items[i],
                previous: i + 1 < items.length ? items[i + 1] : null,
                onDelete: onDelete == null ? null : () => onDelete!(items[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({
    required this.item,
    required this.previous,
    this.onDelete,
  });

  final BodyMeasurement item;
  final BodyMeasurement? previous;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();

    final filled = MeasurementList._fieldGetters.entries
        .where((entry) => entry.value(item) != null)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat.yMMMd(locale).format(item.measuredAt),
                style: LyType.title(c.textPrimary),
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: c.textSecondary,
                ),
                onPressed: onDelete,
                tooltip: l10n.commonRemove,
              ),
          ],
        ),
        const SizedBox(height: LySpace.x2),
        Wrap(
          spacing: LySpace.x4,
          runSpacing: LySpace.x2,
          children: [
            for (final entry in filled)
              _FieldValue(
                label: measurementFieldLabel(l10n, entry.key),
                value: entry.value(item)!,
                delta: previous == null
                    ? null
                    : _delta(entry.value, previous!, item),
              ),
          ],
        ),
        if (item.notes.isNotEmpty) ...[
          const SizedBox(height: LySpace.x2),
          Text(item.notes, style: LyType.bodySm(c.textSecondary)),
        ],
      ],
    );
  }

  double? _delta(
    double? Function(BodyMeasurement) get,
    BodyMeasurement previous,
    BodyMeasurement current,
  ) {
    final prev = get(previous);
    final now = get(current);
    if (prev == null || now == null) return null;
    return now - prev;
  }
}

class _FieldValue extends StatelessWidget {
  const _FieldValue({
    required this.label,
    required this.value,
    required this.delta,
  });

  final String label;
  final double value;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: LyType.caption(c.textSecondary)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatMetric(value),
              style: LyType.numeric(c.textPrimary, size: 15),
            ),
            if (delta != null) ...[
              const SizedBox(width: LySpace.x1),
              DeltaBadge(value: delta),
            ],
          ],
        ),
      ],
    );
  }
}
