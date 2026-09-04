import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/l10n/measurement_l10n.dart';
import '../domain/bioimpedance.dart';
import 'evolution_date_field.dart';

/// Form de lançamento de bioimpedância (P2.4 §2, entrada manual — ADR-012
/// §2). Mesma regra do [MeasurementForm]: campos opcionais, ao menos um
/// preenchido, [onSubmit] só dispara quando a validação passa.
class BioimpedanceForm extends StatefulWidget {
  const BioimpedanceForm({
    required this.onSubmit,
    this.saving = false,
    super.key,
  });

  final ValueChanged<BioimpedanceDraft> onSubmit;
  final bool saving;

  @override
  State<BioimpedanceForm> createState() => _BioimpedanceFormState();
}

class _BioimpedanceFormState extends State<BioimpedanceForm> {
  DateTime _measuredAt = DateTime.now();
  final Map<String, TextEditingController> _controllers = {
    for (final field in bioimpedanceFields) field: TextEditingController(),
  };
  final _notes = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  double? _decimalOf(String field) {
    final raw = _controllers[field]!.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  int? _intOf(String field) {
    final raw = _controllers[field]!.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final draft = BioimpedanceDraft(
      measuredAt: _measuredAt,
      bodyFatPct: _decimalOf('body_fat_pct'),
      muscleMassKg: _decimalOf('muscle_mass_kg'),
      visceralFat: _decimalOf('visceral_fat'),
      bodyWaterPct: _decimalOf('body_water_pct'),
      boneMassKg: _decimalOf('bone_mass_kg'),
      bmrKcal: _intOf('bmr_kcal'),
      notes: _notes.text.trim(),
    );

    if (!draft.hasAnyValue) {
      setState(() => _error = l10n.measurementFormEmpty);
      return;
    }
    setState(() => _error = null);
    widget.onSubmit(draft);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EvolutionDateField(
          label: l10n.evolutionDateLabel,
          value: _measuredAt,
          onChanged: (date) => setState(() => _measuredAt = date),
        ),
        const SizedBox(height: LySpace.x4),
        Wrap(
          spacing: LySpace.x3,
          runSpacing: LySpace.x3,
          children: [
            for (final field in bioimpedanceFields)
              SizedBox(
                width: 156,
                child: LyTextField(
                  key: Key('bioimpedance-form-$field'),
                  label: bioimpedanceFieldLabel(l10n, field),
                  hint: l10n.evolutionValueHint,
                  controller: _controllers[field],
                  keyboardType: field == 'bmr_kcal'
                      ? TextInputType.number
                      : const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
          ],
        ),
        const SizedBox(height: LySpace.x4),
        LyTextField(
          label: l10n.evolutionNotesLabel,
          controller: _notes,
        ),
        if (_error != null) ...[
          const SizedBox(height: LySpace.x3),
          Text(_error!, style: LyType.bodySm(c.danger)),
        ],
        const SizedBox(height: LySpace.x6),
        LyButton(
          key: const Key('bioimpedance-form-save'),
          label: l10n.commonSave,
          loading: widget.saving,
          onPressed: widget.saving ? null : _submit,
        ),
      ],
    );
  }
}
