import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/design_system/design_system.dart';

/// Campo de data opcional com o visual do `LyTextField` (rótulo acima, borda,
/// raio `md`): toca para abrir o `showDatePicker`; o "x" apaga o valor.
/// Textos vêm de quem chama — o campo não conhece l10n.
class LyDateField extends StatelessWidget {
  const LyDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.emptyLabel,
    required this.clearLabel,
    required this.firstDate,
    required this.lastDate,
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  /// Texto quando não há data.
  final String emptyLabel;

  /// Tooltip/rótulo semântico do botão de apagar.
  final String clearLabel;
  final DateTime firstDate;
  final DateTime lastDate;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? lastDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final locale = Localizations.localeOf(context).toString();
    final current = value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: LyType.label(c.textPrimary)),
        const SizedBox(height: LySpace.x2),
        Material(
          color: Colors.transparent,
          child: InkWell(
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
                  Expanded(
                    child: Text(
                      current == null
                          ? emptyLabel
                          : DateFormat.yMMMd(locale).format(current),
                      style: LyType.body(
                        current == null ? c.textSecondary : c.textPrimary,
                      ),
                    ),
                  ),
                  if (current != null)
                    InkResponse(
                      onTap: () => onChanged(null),
                      child: Tooltip(
                        message: clearLabel,
                        child: Padding(
                          // Alvo de toque >= 44 (guideline de acessibilidade).
                          padding: const EdgeInsets.all(LySpace.x3),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
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
