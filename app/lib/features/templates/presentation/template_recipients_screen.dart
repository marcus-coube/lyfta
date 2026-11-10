import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../chat/data/participant_directory.dart';
import '../data/template_repository.dart';
import '../domain/template.dart';
import 'batch_result_view.dart';

/// Quem recebeu o modelo e em que versão está, com os nomes resolvidos no
/// `identity` (o `workout` só guarda ids — ADR-013).
class _RecipientsData {
  const _RecipientsData(this.recipients, this.names);

  final TemplateRecipients recipients;
  final Map<String, String> names;
}

final _recipientsProvider = FutureProvider.autoDispose
    .family<_RecipientsData, String>((ref, templateId) async {
  final recipients =
      await ref.watch(templateRepositoryProvider).recipients(templateId);
  var names = <String, String>{};
  try {
    names = await ref
        .watch(participantDirectoryRepositoryProvider)
        .names(recipients.items.map((r) => r.studentId));
  } catch (_) {
    // Sem nomes a lista ainda serve: cai no título do plano.
  }
  return _RecipientsData(recipients, names);
});

/// "Reaplicar a quem recebeu" (P6.3 §2): quem já está na versão atual e quem
/// teve o plano editado depois (destacado), seleção, aviso de que os ajustes
/// individuais serão substituídos e resultado por aluno.
class TemplateRecipientsScreen extends ConsumerStatefulWidget {
  const TemplateRecipientsScreen({
    required this.templateId,
    this.templateTitle,
    super.key,
  });

  final String templateId;
  final String? templateTitle;

  @override
  ConsumerState<TemplateRecipientsScreen> createState() =>
      _TemplateRecipientsScreenState();
}

class _TemplateRecipientsScreenState
    extends ConsumerState<TemplateRecipientsScreen> {
  final Set<String> _selected = {};
  bool _submitting = false;
  Object? _error;
  List<BatchItem>? _results;
  Map<String, String> _planNames = {};

  String _nameOf(_RecipientsData data, TemplateRecipient r) {
    final name = data.names[r.studentId];
    return name == null || name.isEmpty ? r.title : name;
  }

  Future<void> _submit(_RecipientsData data) async {
    final l10n = AppLocalizations.of(context);
    final chosen = [
      for (final r in data.recipients.items)
        if (_selected.contains(r.planId)) r,
    ];
    final edited = chosen.where((r) => r.editedAfterSource).length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.recipientsConfirmTitle),
        content: Text(
          [
            l10n.recipientsConfirmBody(chosen.length),
            if (edited > 0) l10n.recipientsConfirmEdited(edited),
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('recipients_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.recipientsSubmit),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final items = await ref.read(templateRepositoryProvider).reapply(
            widget.templateId,
            planIds: chosen.map((r) => r.planId).toList(),
          );
      if (!mounted) return;
      setState(() {
        _planNames = {for (final r in chosen) r.planId: _nameOf(data, r)};
        _results = items;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _backToSelection(List<BatchItem> results) {
    ref.invalidate(_recipientsProvider(widget.templateId));
    setState(() {
      _selected
        ..clear()
        ..addAll([
          for (final r in results)
            if (!r.ok && r.planId.isNotEmpty) r.planId,
        ]);
      _results = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(_recipientsProvider(widget.templateId));
    final results = _results;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(l10n.recipientsTitle)),
      body: SafeArea(
        child: results != null
            ? BatchResultView(
                items: results,
                nameOf: (item) => _planNames[item.planId] ?? item.planId,
                okLabel: (item) => l10n.batchItemReapplied(item.versionNo),
                onBackToSelection: () => _backToSelection(results),
              )
            : data.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => LyErrorState(
                  message: describeApiError(context, error),
                  retryable: isRetryableError(error),
                  onRetry: () =>
                      ref.invalidate(_recipientsProvider(widget.templateId)),
                ),
                data: _buildList,
              ),
      ),
    );
  }

  Widget _buildList(_RecipientsData data) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final current = data.recipients.templateVersionNo;
    final items = data.recipients.items;
    final outdated = [
      for (final r in items)
        if (!r.isArchived &&
            (r.sourceVersionNo != current || r.editedAfterSource))
          r,
    ];

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(LySpace.x6),
          child: Text(
            l10n.recipientsEmpty,
            textAlign: TextAlign.center,
            style: LyType.body(c.textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            color: c.danger.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(LySpace.x3),
            child: Text(
              describeApiError(context, _error!),
              style: LyType.bodySm(c.danger),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(LySpace.x4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  [
                    if (widget.templateTitle != null) widget.templateTitle!,
                    l10n.recipientsCurrentVersion(current),
                  ].join(' · '),
                  style: LyType.label(c.textPrimary),
                ),
              ),
              TextButton(
                key: const Key('recipients_select_outdated'),
                onPressed: outdated.isEmpty
                    ? null
                    : () => setState(() {
                          _selected
                            ..clear()
                            ..addAll(outdated.map((r) => r.planId));
                        }),
                child: Text(l10n.recipientsSelectOutdated),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final r in items)
                _RecipientTile(
                  recipient: r,
                  name: _nameOf(data, r),
                  currentVersion: current,
                  selected: _selected.contains(r.planId),
                  onChanged: r.isArchived
                      ? null
                      : (v) => setState(() {
                            if (v ?? false) {
                              _selected.add(r.planId);
                            } else {
                              _selected.remove(r.planId);
                            }
                          }),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(LySpace.x4),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: LyButton(
            key: const Key('recipients_submit'),
            label: l10n.recipientsSubmit,
            loading: _submitting,
            onPressed:
                _selected.isEmpty || _submitting ? null : () => _submit(data),
          ),
        ),
      ],
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({
    required this.recipient,
    required this.name,
    required this.currentVersion,
    required this.selected,
    required this.onChanged,
  });

  final TemplateRecipient recipient;
  final String name;
  final int currentVersion;
  final bool selected;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final r = recipient;
    final upToDate = r.sourceVersionNo == currentVersion;

    return CheckboxListTile(
      key: Key('recipient_${r.planId}'),
      value: selected,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(name, style: LyType.label(c.textPrimary)),
      subtitle: Wrap(
        spacing: LySpace.x2,
        children: [
          Text(
            upToDate
                ? l10n.recipientsUpToDate
                : l10n.recipientsOutdated(r.sourceVersionNo),
            style: LyType.caption(c.textSecondary),
          ),
          if (r.editedAfterSource)
            Text(
              l10n.recipientsEdited,
              key: Key('recipient_edited_${r.planId}'),
              style: LyType.caption(c.warning),
            ),
          if (r.isArchived)
            Text(
              l10n.recipientsArchived,
              style: LyType.caption(c.textSecondary),
            ),
        ],
      ),
    );
  }
}
