import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/http/api_exception_l10n.dart';
import '../../../../core/l10n/gen/app_localizations.dart';
import '../../../../shared/domain/plan.dart';
import '../../../../shared/widgets/ly_error_state.dart';
import '../../../chat/data/participant_directory.dart';
import '../../data/plan_repository.dart';

typedef _History = ({List<PlanVersionSummary> items, Map<String, String> names});

/// Histórico + nome de quem publicou (o `workout` só guarda o id do autor,
/// ADR-013: o nome é do `identity`). Sem nomes a lista ainda serve.
final _historyProvider =
    FutureProvider.autoDispose.family<_History, String>((ref, planId) async {
  final items = await ref.watch(planRepositoryProvider).versions(planId);
  var names = <String, String>{};
  final authors = items.map((v) => v.publishedBy).whereType<String>();
  if (authors.isNotEmpty) {
    try {
      names = await ref
          .watch(participantDirectoryRepositoryProvider)
          .names(authors);
    } catch (_) {}
  }
  return (items: items, names: names);
});

/// Histórico de versões do plano (P6.4). Devolve a versão escolhida; o
/// builder abre a publicada em leitura e a rascunho para edição.
Future<PlanVersionSummary?> showVersionHistory(
  BuildContext context, {
  required String planId,
}) {
  return showModalBottomSheet<PlanVersionSummary>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VersionHistorySheet(planId: planId),
  );
}

class _VersionHistorySheet extends ConsumerWidget {
  const _VersionHistorySheet({required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(_historyProvider(planId));
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toString());

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LySpace.x4),
              child: Text(
                l10n.builderHistory,
                style: LyType.title(c.textPrimary),
              ),
            ),
            const SizedBox(height: LySpace.x2),
            Flexible(
              child: history.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(LySpace.x6),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => LyErrorState(
                  message: describeApiError(context, error),
                  retryable: isRetryableError(error),
                  onRetry: () => ref.invalidate(_historyProvider(planId)),
                ),
                data: (data) {
                  if (data.items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(LySpace.x4),
                      child: Text(
                        l10n.builderHistoryEmpty,
                        style: LyType.body(c.textSecondary),
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final v in data.items)
                        ListTile(
                          key: Key('history_v${v.versionNo}'),
                          title: Text(
                            v.isDraft
                                ? l10n.builderDraftVersion(v.versionNo)
                                : l10n.builderPublishedVersion(v.versionNo),
                            style: LyType.label(c.textPrimary),
                          ),
                          subtitle: Text(
                            [
                              if (v.publishedAt != null)
                                date.format(v.publishedAt!),
                              if (data.names[v.publishedBy] case final name?
                                  when name.isNotEmpty)
                                l10n.builderHistoryBy(name),
                              l10n.builderHistoryCounts(
                                v.daysCount,
                                v.exercisesCount,
                              ),
                            ].join(' · '),
                            style: LyType.caption(c.textSecondary),
                          ),
                          trailing: Icon(
                            v.isDraft ? Icons.edit_outlined : Icons.visibility,
                            size: 18,
                            color: c.textSecondary,
                          ),
                          onTap: () => Navigator.of(context).pop(v),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
