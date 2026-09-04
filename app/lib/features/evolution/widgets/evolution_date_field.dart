import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';

/// Campo de data com o mesmo visual do `LyTextField` (rótulo acima, borda,
/// raio `md`), mas somente leitura — toca para abrir o `showDatePicker` do
/// Flutter. Usado nos três lançamentos da tela Evolução (medida,
/// bioimpedância, foto): sempre uma data, nunca hora.
class EvolutionDateField extends StatelessWidget {
  const EvolutionDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final locale = Localizations.localeOf(context).toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: LyType.label(c.textPrimary)),
        const SizedBox(height: LySpace.x2),
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('evolution-date-field'),
            borderRadius: LyRadius.md,
            onTap: () => _pick(context),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LySpace.x4,
                vertical: LySpace.x3,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: c.border),
                borderRadius: LyRadius.md,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: c.textSecondary,
                  ),
                  const SizedBox(width: LySpace.x2),
                  Text(
                    DateFormat.yMMMd(locale).format(value),
                    style: LyType.body(c.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
