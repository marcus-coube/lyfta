import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/format/metric_format.dart';
import '../../../shared/l10n/measurement_l10n.dart';
import '../domain/bioimpedance.dart';
import 'delta_badge.dart';

/// Histórico de bioimpedância — mesmo desenho do [MeasurementList]: mais
/// recente primeiro, delta contra o registro anterior por campo.
class BioimpedanceList extends StatelessWidget {
  const BioimpedanceList({
    required this.items,
    this.onDelete,
    super.key,
  });

  final List<BioimpedanceRecord> items;
  final ValueChanged<BioimpedanceRecord>? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;

    if (items.isEmpty) {
      return Text(
        l10n.evolutionBioimpedanceEmpty,
        style: LyType.body(c.textSecondary),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: LySpace.x3),
            child: LyCard(
              child: _BioimpedanceRow(
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

class _BioimpedanceRow extends StatelessWidget {
  const _BioimpedanceRow({
    required this.item,
    required this.previous,
    this.onDelete,
  });

  final BioimpedanceRecord item;
  final BioimpedanceRecord? previous;
  final VoidCallback? onDelete;

  static const _numericFields = <String, double? Function(BioimpedanceRecord)>{
    'body_fat_pct': _bodyFat,
    'muscle_mass_kg': _muscleMass,
    'visceral_fat': _visceralFat,
    'body_water_pct': _bodyWater,
    'bone_mass_kg': _boneMass,
  };

  static double? _bodyFat(BioimpedanceRecord r) => r.bodyFatPct;
  static double? _muscleMass(BioimpedanceRecord r) => r.muscleMassKg;
  static double? _visceralFat(BioimpedanceRecord r) => r.visceralFat;
  static double? _bodyWater(BioimpedanceRecord r) => r.bodyWaterPct;
  static double? _boneMass(BioimpedanceRecord r) => r.boneMassKg;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();

    final filled = _numericFields.entries
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
                label: bioimpedanceFieldLabel(l10n, entry.key),
                value: entry.value(item)!,
                delta: previous == null
                    ? null
                    : _delta(entry.value, previous!, item),
              ),
            if (item.bmrKcal != null)
              _FieldValue(
                label: bioimpedanceFieldLabel(l10n, 'bmr_kcal'),
                value: item.bmrKcal!.toDouble(),
                delta: previous?.bmrKcal == null || item.bmrKcal == null
                    ? null
                    : (item.bmrKcal! - previous!.bmrKcal!).toDouble(),
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
    double? Function(BioimpedanceRecord) get,
    BioimpedanceRecord previous,
    BioimpedanceRecord current,
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
