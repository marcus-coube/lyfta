import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/l10n/taxonomy_l10n.dart';
import '../../../shared/domain/exercise.dart';
import 'exercise_form_screen.dart';
import 'library_controller.dart';
import '../../../shared/widgets/exercise_media.dart';

/// Biblioteca de exercícios do professor (P1.6): busca, filtros da taxonomia
/// e criação de exercício próprio.
///
/// A biblioteca global é somente leitura (ADR-010 §3) — abrir um global
/// oferece **duplicar**, que é ler e criar de novo com o mesmo conteúdo.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      ref.read(libraryProvider.notifier).loadMore();
    }
  }

  Future<void> _openForm({Exercise? exercise, bool duplicate = false}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExerciseFormScreen(source: exercise, duplicate: duplicate),
      ),
    );
    if (saved ?? false) {
      ref.read(libraryProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(libraryFilterProvider);
    final state = ref.watch(libraryProvider);

    return Scaffold(
      backgroundColor: c.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        icon: const Icon(Icons.add),
        label: Text(l10n.libraryNewExercise),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LySpace.x4,
              LySpace.x4,
              LySpace.x4,
              LySpace.x2,
            ),
            child: LyTextField(
              label: l10n.librarySearchLabel,
              hint: l10n.librarySearchHint,
              controller: _searchController,
              prefixIcon: Icons.search,
              onChanged: (value) => ref
                  .read(libraryFilterProvider.notifier)
                  .update((f) => f.copyWith(query: value)),
            ),
          ),
          _FilterBar(filter: filter),
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(
                message: describeApiError(context, error),
                onRetry: () => ref.read(libraryProvider.notifier).refresh(),
              ),
              data: (data) {
                if (data.items.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.libraryEmpty,
                      style: LyType.body(c.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    LySpace.x4,
                    LySpace.x2,
                    LySpace.x4,
                    LySpace.x16,
                  ),
                  itemCount: data.items.length + (data.hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: LySpace.x2),
                  itemBuilder: (context, index) {
                    if (index >= data.items.length) {
                      return const Padding(
                        padding: EdgeInsets.all(LySpace.x4),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final exercise = data.items[index];
                    return ExerciseTile(
                      exercise: exercise,
                      onTap: () => _openForm(
                        exercise: exercise,
                        duplicate: exercise.isGlobal,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha da biblioteca — mídia, nome e a taxonomia traduzida. Reutilizada
/// pelo seletor de exercício do builder.
class ExerciseTile extends StatelessWidget {
  const ExerciseTile({
    required this.exercise,
    this.onTap,
    this.trailing,
    super.key,
  });

  final Exercise exercise;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return LyCard(
      onTap: onTap,
      child: Row(
        children: [
          ExerciseMedia(exercise: exercise),
          const SizedBox(width: LySpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  style: LyType.label(c.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: LySpace.x1),
                Text(
                  '${muscleLabel(l10n, exercise.primaryMuscle)}'
                  ' · ${equipmentLabel(l10n, exercise.equipment)}',
                  style: LyType.caption(c.textSecondary),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          if (trailing == null && exercise.isGlobal)
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
                l10n.libraryGlobalBadge,
                style: LyType.caption(c.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Filtros de músculo e equipamento. São códigos da taxonomia (ADR-010 §4)
/// traduzidos na hora de desenhar — o backend recusa qualquer outro valor.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter});

  final ExerciseFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: LySpace.x4),
        children: [
          _FilterChipMenu(
            label: filter.muscle == null
                ? l10n.libraryFilterMuscle
                : muscleLabel(l10n, filter.muscle!),
            selected: filter.muscle != null,
            options: ExerciseTaxonomy.muscles,
            optionLabel: (code) => muscleLabel(l10n, code),
            clearLabel: l10n.libraryFilterAll,
            onSelected: (code) => ref
                .read(libraryFilterProvider.notifier)
                .update(
                  (f) => code == null
                      ? f.copyWith(clearMuscle: true)
                      : f.copyWith(muscle: code),
                ),
          ),
          const SizedBox(width: LySpace.x2),
          _FilterChipMenu(
            label: filter.equipment == null
                ? l10n.libraryFilterEquipment
                : equipmentLabel(l10n, filter.equipment!),
            selected: filter.equipment != null,
            options: ExerciseTaxonomy.equipment,
            optionLabel: (code) => equipmentLabel(l10n, code),
            clearLabel: l10n.libraryFilterAll,
            onSelected: (code) => ref
                .read(libraryFilterProvider.notifier)
                .update(
                  (f) => code == null
                      ? f.copyWith(clearEquipment: true)
                      : f.copyWith(equipment: code),
                ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipMenu extends StatelessWidget {
  const _FilterChipMenu({
    required this.label,
    required this.selected,
    required this.options,
    required this.optionLabel,
    required this.clearLabel,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final List<String> options;
  final String Function(String code) optionLabel;
  final String clearLabel;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return PopupMenuButton<String?>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem<String?>(child: Text(clearLabel)),
        ...options.map(
          (code) => PopupMenuItem<String?>(
            value: code,
            child: Text(optionLabel(code)),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LySpace.x4,
          vertical: LySpace.x3,
        ),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface,
          borderRadius: LyRadius.pill,
          border: Border.all(color: selected ? c.accent : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: LyType.caption(selected ? c.onAccent : c.textSecondary),
            ),
            Icon(
              Icons.expand_more,
              size: 16,
              color: selected ? c.onAccent : c.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LySpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: LyType.body(c.textSecondary),
            ),
            const SizedBox(height: LySpace.x4),
            LyButton(
              label: l10n.commonRetry,
              variant: LyButtonVariant.secondary,
              expanded: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
