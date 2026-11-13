import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/http/api_exception_l10n.dart';
import '../../../../core/l10n/gen/app_localizations.dart';
import '../../../../shared/domain/plan.dart';
import '../../../variations/presentation/variation_form_dialog.dart';
import '../../../variations/presentation/variations_providers.dart';

/// Tamanho máximo do rótulo da série (CHECK do servidor, ADR-019).
const int setLabelMaxLength = 24;

/// Pede o rótulo da série. Devolve o texto aparado (vazio = remover o
/// rótulo) ou `null` no cancelar. O diálogo é dono do controller.
Future<String?> showSetLabelDialog(BuildContext context, {String? initial}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SetLabelDialog(initial: initial ?? ''),
  );
}

class _SetLabelDialog extends StatefulWidget {
  const _SetLabelDialog({required this.initial});

  final String initial;

  @override
  State<_SetLabelDialog> createState() => _SetLabelDialogState();
}

class _SetLabelDialogState extends State<_SetLabelDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pick(String text) {
    // O valor gravado é o texto, não um código: a sugestão só preenche.
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;
    final suggestions = [
      l10n.builderLabelSuggestWarmup,
      l10n.builderLabelSuggestRecognition,
      l10n.builderLabelSuggestTopSet,
      l10n.builderLabelSuggestBackOff,
    ];

    return AlertDialog(
      title: Text(l10n.builderLabelTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LyTextField(
              key: const Key('set-label-field'),
              label: l10n.builderLabelField,
              controller: _controller,
              autofocus: true,
              maxLength: setLabelMaxLength,
            ),
            const SizedBox(height: LySpace.x2),
            Wrap(
              spacing: LySpace.x2,
              runSpacing: LySpace.x2,
              children: [
                for (final text in suggestions)
                  ActionChip(
                    key: Key('set-label-suggestion-$text'),
                    label: Text(text),
                    onPressed: () => _pick(text),
                  ),
              ],
            ),
            const SizedBox(height: LySpace.x2),
            Text(
              l10n.builderLabelHint,
              style: LyType.caption(c.textSecondary),
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
          key: const Key('set-label-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

/// Escolha da variação: `null` = cancelou; `(variation: null)` = "Nenhuma".
typedef VariationChoice = ({SetVariation? variation});

Future<VariationChoice?> showVariationPicker(
  BuildContext context, {
  String? currentId,
}) {
  return showDialog<VariationChoice>(
    context: context,
    builder: (_) => _VariationPicker(currentId: currentId),
  );
}

class _VariationPicker extends ConsumerStatefulWidget {
  const _VariationPicker({this.currentId});

  final String? currentId;

  @override
  ConsumerState<_VariationPicker> createState() => _VariationPickerState();
}

class _VariationPickerState extends ConsumerState<_VariationPicker> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _createNew() async {
    final created = await showVariationFormDialog(
      context,
      initialName: _query.trim(),
    );
    if (created != null && mounted) {
      Navigator.of(context).pop<VariationChoice>((variation: created));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;
    final items = ref.watch(variationPickerProvider(_query.trim()));

    return AlertDialog(
      title: Text(l10n.builderVariationTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LyTextField(
              key: const Key('set-variation-search'),
              label: l10n.builderVariationSearch,
              controller: _search,
              prefixIcon: Icons.search,
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: LySpace.x2),
            ListTile(
              key: const Key('set-variation-none'),
              dense: true,
              title: Text(l10n.builderVariationNone),
              selected: widget.currentId == null,
              onTap: () => Navigator.of(context)
                  .pop<VariationChoice>((variation: null)),
            ),
            Flexible(
              child: items.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(LySpace.x4),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(LySpace.x2),
                  child: Text(
                    describeApiError(context, error),
                    style: LyType.bodySm(c.danger),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(LySpace.x2),
                      child: Text(
                        l10n.builderVariationEmpty,
                        style: LyType.caption(c.textSecondary),
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final v in list)
                        ListTile(
                          key: Key('set-variation-${v.id}'),
                          dense: true,
                          title: Text(v.name),
                          subtitle: v.description.isEmpty
                              ? null
                              : Text(
                                  v.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          selected: v.id == widget.currentId,
                          onTap: () => Navigator.of(context)
                              .pop<VariationChoice>((variation: v)),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('set-variation-new'),
          onPressed: _createNew,
          child: Text(l10n.builderVariationNew),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}
