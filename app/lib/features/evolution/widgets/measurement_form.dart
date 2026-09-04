import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/l10n/measurement_l10n.dart';
import '../domain/measurement.dart';
import 'evolution_date_field.dart';

/// Form de lançamento de medida corporal (P2.4 §2) — reusável entre o
/// aluno (P2.4) e o coach (P2.5, avaliação presencial).
///
/// Só o que o aluno mediu naquele dia é obrigatório de verdade: os 14 campos
/// são opcionais, mas ao menos um precisa estar preenchido — um lançamento
/// só com a data não vira uma linha no histórico ([MeasurementDraft.hasAnyValue]).
/// O widget não fala com o repositório: [onSubmit] só dispara quando a
/// validação passa, e quem chama decide o que fazer com o rascunho.
class MeasurementForm extends StatefulWidget {
  const MeasurementForm({
    required this.onSubmit,
    this.saving = false,
    super.key,
  });

  final ValueChanged<MeasurementDraft> onSubmit;
  final bool saving;

  @override
  State<MeasurementForm> createState() => _MeasurementFormState();
}

class _MeasurementFormState extends State<MeasurementForm> {
  DateTime _measuredAt = DateTime.now();
  final Map<String, TextEditingController> _controllers = {
    for (final field in bodyMeasurementFields) field: TextEditingController(),
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

  double? _valueOf(String field) {
    final raw = _controllers[field]!.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final draft = MeasurementDraft(
      measuredAt: _measuredAt,
      weightKg: _valueOf('weight_kg'),
      heightCm: _valueOf('height_cm'),
      neckCm: _valueOf('neck_cm'),
      shoulderCm: _valueOf('shoulder_cm'),
      chestCm: _valueOf('chest_cm'),
      waistCm: _valueOf('waist_cm'),
      abdomenCm: _valueOf('abdomen_cm'),
      hipCm: _valueOf('hip_cm'),
      armLCm: _valueOf('arm_l_cm'),
      armRCm: _valueOf('arm_r_cm'),
      thighLCm: _valueOf('thigh_l_cm'),
      thighRCm: _valueOf('thigh_r_cm'),
      calfLCm: _valueOf('calf_l_cm'),
      calfRCm: _valueOf('calf_r_cm'),
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
            for (final field in bodyMeasurementFields)
              SizedBox(
                width: 156,
                child: LyTextField(
                  key: Key('measurement-form-$field'),
                  label: measurementFieldLabel(l10n, field),
                  hint: l10n.evolutionValueHint,
                  controller: _controllers[field],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
          key: const Key('measurement-form-save'),
          label: l10n.commonSave,
          loading: widget.saving,
          onPressed: widget.saving ? null : _submit,
        ),
      ],
    );
  }
}
