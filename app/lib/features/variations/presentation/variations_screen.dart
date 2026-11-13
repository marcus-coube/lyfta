import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/domain/plan.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../data/variation_repository.dart';
import 'variation_form_dialog.dart';
import 'variations_providers.dart';

/// Variações de série do tenant (ADR-019): busca, criar/editar em diálogo,
/// arquivar/desarquivar e filtro de arquivadas. Segmento "Variações" da aba
/// Biblioteca do coach.
class VariationsScreen extends ConsumerStatefulWidget {
  const VariationsScreen({super.key});

  @override
  ConsumerState<VariationsScreen> createState() => _VariationsScreenState();
}

class _VariationsScreenState extends ConsumerState<VariationsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit(SetVariation? variation) async {
    final saved = await showVariationFormDialog(context, variation: variation);
    if (saved == null || !mounted) return;
    ref.invalidate(variationsListProvider);
    _snack(AppLocalizations.of(context).variationsSaved);
  }

  Future<void> _toggleArchived(SetVariation variation) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(variationRepositoryProvider)
          .setArchived(variation.id, archived: !variation.archived);
      ref.invalidate(variationsListProvider);
      _snack(
        variation.archived
            ? l10n.variationsUnarchivedDone
            : l10n.variationsArchivedDone,
      );
    } catch (error) {
      if (mounted) _snack(describeApiError(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(variationFilterProvider);
    final state = ref.watch(variationsListProvider);

    return Scaffold(
      backgroundColor: c.background,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('variation_new'),
        onPressed: () => _edit(null),
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        icon: const Icon(Icons.add),
        label: Text(l10n.variationsNew),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LySpace.x4,
              LySpace.x2,
              LySpace.x4,
              LySpace.x2,
            ),
            child: LyTextField(
              key: const Key('variation_search'),
              label: l10n.variationsSearchLabel,
              controller: _search,
              prefixIcon: Icons.search,
              onChanged: (value) => ref
                  .read(variationFilterProvider.notifier)
                  .update((f) => (query: value, showArchived: f.showArchived)),
            ),
          ),
          SwitchListTile(
            key: const Key('variation_show_archived'),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: LySpace.x4),
            title: Text(
              l10n.variationsShowArchived,
              style: LyType.caption(c.textSecondary),
            ),
            value: filter.showArchived,
            onChanged: (value) => ref
                .read(variationFilterProvider.notifier)
                .update((f) => (query: f.query, showArchived: value)),
          ),
          Expanded(
            child: state.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(LySpace.x4),
                child: Column(
                  children: [
                    LySkeletonListTile(),
                    SizedBox(height: LySpace.x3),
                    LySkeletonListTile(),
                  ],
                ),
              ),
              error: (error, _) => LyErrorState(
                message: describeApiError(context, error),
                retryable: isRetryableError(error),
                onRetry: () => ref.invalidate(variationsListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(LySpace.x4),
                      child: Text(
                        l10n.variationsEmpty,
                        textAlign: TextAlign.center,
                        style: LyType.body(c.textSecondary),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    LySpace.x4,
                    LySpace.x2,
                    LySpace.x4,
                    LySpace.x16,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: LySpace.x2),
                  itemBuilder: (context, index) => _VariationCard(
                    variation: items[index],
                    onEdit: () => _edit(items[index]),
                    onToggleArchived: () => _toggleArchived(items[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VariationCard extends StatelessWidget {
  const _VariationCard({
    required this.variation,
    required this.onEdit,
    required this.onToggleArchived,
  });

  final SetVariation variation;
  final VoidCallback onEdit;
  final VoidCallback onToggleArchived;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final archived = variation.archived;

    return LyCard(
      key: Key('variation_${variation.id}'),
      padding: const EdgeInsets.all(LySpace.x4),
      onTap: onEdit,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        variation.name,
                        style: LyType.label(
                          archived ? c.textSecondary : c.textPrimary,
                        ),
                      ),
                    ),
                    if (archived) ...[
                      const SizedBox(width: LySpace.x2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: LySpace.x2,
                          vertical: LySpace.x1,
                        ),
                        decoration: BoxDecoration(
                          color: c.surfaceElevated,
                          borderRadius: LyRadius.pill,
                        ),
                        child: Text(
                          l10n.variationsArchivedBadge,
                          style: LyType.caption(c.textSecondary),
                        ),
                      ),
                    ],
                  ],
                ),
                if (variation.description.isNotEmpty)
                  Text(
                    variation.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LyType.caption(c.textSecondary),
                  ),
              ],
            ),
          ),
          IconButton(
            key: Key('variation_archive_${variation.id}'),
            tooltip:
                archived ? l10n.variationsUnarchive : l10n.variationsArchive,
            icon: Icon(
              archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            ),
            color: c.textSecondary,
            onPressed: onToggleArchived,
          ),
        ],
      ),
    );
  }
}
