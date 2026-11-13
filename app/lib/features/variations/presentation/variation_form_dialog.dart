import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/domain/plan.dart';
import '../data/variation_repository.dart';

/// Cria ou edita uma variação (nome + descrição). Devolve a variação salva,
/// ou `null` no cancelar.
///
/// O diálogo é dono dos controllers (mesmo molde de
/// `template_form_dialog.dart`) e conversa com o servidor: nome repetido
/// (409 `variation_name_taken`) vira mensagem no próprio campo, sem fechar.
Future<SetVariation?> showVariationFormDialog(
  BuildContext context, {
  SetVariation? variation,
  String initialName = '',
}) {
  return showDialog<SetVariation>(
    context: context,
    builder: (_) =>
        _VariationFormDialog(variation: variation, initialName: initialName),
  );
}

class _VariationFormDialog extends ConsumerStatefulWidget {
  const _VariationFormDialog({this.variation, this.initialName = ''});

  final SetVariation? variation;
  final String initialName;

  @override
  ConsumerState<_VariationFormDialog> createState() =>
      _VariationFormDialogState();
}

class _VariationFormDialogState extends ConsumerState<_VariationFormDialog> {
  late final _name = TextEditingController(
    text: widget.variation?.name ?? widget.initialName,
  );
  late final _description =
      TextEditingController(text: widget.variation?.description ?? '');
  bool _saving = false;
  String? _nameError;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _saving = true;
      _nameError = null;
      _error = null;
    });
    try {
      final repository = ref.read(variationRepositoryProvider);
      final description = _description.text.trim();
      final existing = widget.variation;
      final saved = existing == null
          ? await repository.create(name: name, description: description)
          : await repository.update(
              existing.id,
              name: name,
              description: description,
            );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      final message = describeApiError(context, error);
      setState(() {
        _saving = false;
        if (error is ApiException && error.code == 'variation_name_taken') {
          _nameError = message;
        } else {
          _error = message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final editing = widget.variation != null;

    return AlertDialog(
      title: Text(editing ? l10n.variationsEdit : l10n.variationsNew),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LyTextField(
              key: const Key('variation_name'),
              label: l10n.variationsNameLabel,
              controller: _name,
              autofocus: true,
              maxLength: 40,
              errorText: _nameError,
              onChanged: (_) => setState(() => _nameError = null),
            ),
            const SizedBox(height: LySpace.x3),
            LyTextField(
              key: const Key('variation_description'),
              label: l10n.variationsDescriptionLabel,
              controller: _description,
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
            ),
            if (_error != null) ...[
              const SizedBox(height: LySpace.x2),
              Text(_error!, style: LyType.bodySm(c.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('variation_save'),
          onPressed: _saving || _name.text.trim().isEmpty ? null : _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
