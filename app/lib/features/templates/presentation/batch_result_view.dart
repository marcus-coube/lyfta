import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/template.dart';

/// Resultado por item de um lote (aplicar ou reaplicar): quem deu certo e, de
/// quem falhou, o motivo traduzido pelo `code` (ADR-011 §3).
class BatchResultView extends StatelessWidget {
  const BatchResultView({
    required this.items,
    required this.nameOf,
    required this.okLabel,
    required this.onBackToSelection,
    super.key,
  });

  final List<BatchItem> items;
  final String Function(BatchItem item) nameOf;
  final String Function(BatchItem item) okLabel;
  final VoidCallback onBackToSelection;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final okCount = items.where((i) => i.ok).length;
    final failed = items.length - okCount;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(LySpace.x4),
            children: [
              Text(
                l10n.batchResultTitle,
                style: LyType.title(c.textPrimary),
              ),
              const SizedBox(height: LySpace.x1),
              Text(
                l10n.batchResultSummary(okCount, items.length),
                key: const Key('batch_result_summary'),
                style: LyType.body(c.textSecondary),
              ),
              const SizedBox(height: LySpace.x4),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: LySpace.x2),
                  child: LyCard(
                    padding: const EdgeInsets.all(LySpace.x3),
                    child: Row(
                      children: [
                        Icon(
                          item.ok ? Icons.check_circle : Icons.error_outline,
                          color: item.ok ? c.success : c.danger,
                        ),
                        const SizedBox(width: LySpace.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nameOf(item),
                                style: LyType.label(c.textPrimary),
                              ),
                              Text(
                                item.ok
                                    ? okLabel(item)
                                    : (item.error?.message(l10n) ??
                                        l10n.errorInternal),
                                style: LyType.caption(
                                  item.ok ? c.textSecondary : c.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
          // Em coluna: o rótulo de "tentar de novo" não cabe na metade da
          // largura de um celular.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (failed > 0) ...[
                LyButton(
                  key: const Key('batch_back'),
                  label: l10n.batchBackToSelection,
                  variant: LyButtonVariant.secondary,
                  onPressed: onBackToSelection,
                ),
                const SizedBox(height: LySpace.x2),
              ],
              LyButton(
                key: const Key('batch_done'),
                label: l10n.batchDone,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
