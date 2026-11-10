import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../data/template_repository.dart';
import '../domain/template.dart';

/// O que o coach escolheu no diálogo "Aplicar modelo".
typedef AppliedTemplateChoice = ({TemplateSummary template, bool publish});

/// Escolha de um modelo publicado para aplicar a **um** aluno, a partir da
/// aba Treino da ficha (P6.3 §3). Para vários alunos de uma vez o caminho é a
/// aba Modelos.
Future<AppliedTemplateChoice?> showApplyTemplateDialog(BuildContext context) {
  return showDialog<AppliedTemplateChoice>(
    context: context,
    builder: (context) => const _ApplyTemplateDialog(),
  );
}

class _ApplyTemplateDialog extends ConsumerStatefulWidget {
  const _ApplyTemplateDialog();

  @override
  ConsumerState<_ApplyTemplateDialog> createState() =>
      _ApplyTemplateDialogState();
}

class _ApplyTemplateDialogState extends ConsumerState<_ApplyTemplateDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _generation = 0;

  List<TemplateSummary> _templates = const [];
  bool _loading = true;
  Object? _error;
  TemplateSummary? _picked;
  bool _publish = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(templateRepositoryProvider)
          .list(query: _search.text, limit: 50);
      if (!mounted || generation != _generation) return;
      setState(() {
        _templates = page.items.where((t) => t.canAssign).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.applyModelTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LyTextField(
              label: l10n.templatesSearchLabel,
              hint: l10n.templatesSearchHint,
              controller: _search,
              prefixIcon: Icons.search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _load);
              },
            ),
            const SizedBox(height: LySpace.x3),
            Flexible(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Text(
                          describeApiError(context, _error!),
                          style: LyType.bodySm(c.danger),
                        )
                      : _templates.isEmpty
                          ? Text(
                              l10n.applyModelEmpty,
                              style: LyType.body(c.textSecondary),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                for (final t in _templates)
                                  ListTile(
                                    key: Key('apply_model_${t.id}'),
                                    selected: _picked?.id == t.id,
                                    selectedTileColor: c.surfaceElevated,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: LyRadius.md,
                                    ),
                                    title: Text(t.title),
                                    subtitle: Text(
                                      [
                                        l10n.builderPublishedVersion(
                                          t.publishedVersionNo,
                                        ),
                                        l10n.templatesDays(t.daysCount),
                                      ].join(' · '),
                                    ),
                                    trailing: _picked?.id == t.id
                                        ? Icon(Icons.check, color: c.accent)
                                        : null,
                                    onTap: () => setState(() => _picked = t),
                                  ),
                              ],
                            ),
            ),
            const SizedBox(height: LySpace.x3),
            SwitchListTile(
              key: const Key('apply_model_publish'),
              contentPadding: EdgeInsets.zero,
              value: _publish,
              onChanged: (v) => setState(() => _publish = v),
              title: Text(l10n.assignPublishNow),
              subtitle: Text(
                l10n.assignPublishNowHint,
                style: LyType.caption(c.textSecondary),
              ),
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
          key: const Key('apply_model_submit'),
          onPressed: _picked == null
              ? null
              : () => Navigator.of(context)
                  .pop((template: _picked!, publish: _publish)),
          child: Text(l10n.assignSubmit),
        ),
      ],
    );
  }
}
