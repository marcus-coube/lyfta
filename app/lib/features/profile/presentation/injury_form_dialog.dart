import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/l10n/profile_l10n.dart';
import '../../../shared/widgets/ly_date_field.dart';
import '../domain/student_profile.dart';

/// Formulário de lesão (P5.5): região, descrição e desde quando. Fecha com o
/// [InjuryInput] ou `null` se cancelou.
Future<InjuryInput?> showInjuryFormDialog(BuildContext context) {
  return showDialog<InjuryInput>(
    context: context,
    builder: (_) => const InjuryFormDialog(),
  );
}

class InjuryFormDialog extends StatefulWidget {
  const InjuryFormDialog({super.key});

  @override
  State<InjuryFormDialog> createState() => _InjuryFormDialogState();
}

class _InjuryFormDialogState extends State<InjuryFormDialog> {
  final _description = TextEditingController();
  String? _region;
  DateTime? _since;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  bool get _valid => _region != null && _description.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();

    return AlertDialog(
      title: Text(l10n.injuryFormTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.injuryRegionLabel, style: LyType.label(c.textPrimary)),
            const SizedBox(height: LySpace.x2),
            DropdownButtonFormField<String>(
              key: const Key('injury_region'),
              initialValue: _region,
              isExpanded: true,
              items: [
                for (final code in bodyRegionCodes)
                  DropdownMenuItem(
                    value: code,
                    child: Text(bodyRegionLabel(l10n, code)),
                  ),
              ],
              onChanged: (code) => setState(() => _region = code),
            ),
            const SizedBox(height: LySpace.x3),
            LyTextField(
              key: const Key('injury_description'),
              label: l10n.injuryDescriptionLabel,
              controller: _description,
              minLines: 2,
              maxLines: 4,
              maxLength: injuryDescriptionMaxLength,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: LySpace.x3),
            LyDateField(
              label: l10n.injurySinceLabel,
              value: _since,
              emptyLabel: l10n.injurySinceEmpty,
              clearLabel: l10n.injurySinceClear,
              firstDate: DateTime(1900),
              lastDate: DateTime(now.year, now.month, now.day),
              onChanged: (value) => setState(() => _since = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('injury_save'),
          onPressed: _valid
              ? () => Navigator.of(context).pop(
                    InjuryInput(
                      bodyRegion: _region!,
                      description: _description.text.trim(),
                      since: _since,
                    ),
                  )
              : null,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
