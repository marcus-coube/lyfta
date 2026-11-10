import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';

/// Título (e descrição, opcional) de um modelo novo.
typedef TemplateFormResult = ({String title, String description});

/// Pede título e, com [withDescription], descrição de um modelo (P6.3).
/// Devolve `null` no cancelar.
///
/// O diálogo é dono dos controllers: descartá-los logo depois do
/// `showDialog` retornar quebra o app (os campos ainda estão montados
/// durante a animação de saída — assert `_dependents.isEmpty`).
Future<TemplateFormResult?> showTemplateFormDialog(
  BuildContext context, {
  required String heading,
  String initialTitle = '',
  bool withDescription = false,
  Key? confirmKey,
}) {
  return showDialog<TemplateFormResult>(
    context: context,
    builder: (_) => _TemplateFormDialog(
      heading: heading,
      initialTitle: initialTitle,
      withDescription: withDescription,
      confirmKey: confirmKey,
    ),
  );
}

class _TemplateFormDialog extends StatefulWidget {
  const _TemplateFormDialog({
    required this.heading,
    required this.initialTitle,
    required this.withDescription,
    this.confirmKey,
  });

  final String heading;
  final String initialTitle;
  final bool withDescription;
  final Key? confirmKey;

  @override
  State<_TemplateFormDialog> createState() => _TemplateFormDialogState();
}

class _TemplateFormDialogState extends State<_TemplateFormDialog> {
  late final _title = TextEditingController.fromValue(
    TextEditingValue(
      text: widget.initialTitle,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialTitle.length,
      ),
    ),
  );
  final _description = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop<TemplateFormResult>(
      (title: title, description: _description.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.heading),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LyTextField(
            label: l10n.templatesTitleLabel,
            controller: _title,
            autofocus: true,
          ),
          if (widget.withDescription) ...[
            const SizedBox(height: LySpace.x3),
            LyTextField(
              label: l10n.templatesDescriptionLabel,
              controller: _description,
              minLines: 2,
              maxLines: 4,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: widget.confirmKey,
          onPressed: _submit,
          child: Text(l10n.commonCreate),
        ),
      ],
    );
  }
}
